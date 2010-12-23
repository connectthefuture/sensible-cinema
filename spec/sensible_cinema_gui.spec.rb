=begin
Copyright 2010, Roger Pack 
This file is part of Sensible Cinema.

    Sensible Cinema is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    Sensible Cinema is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with Sensible Cinema.  If not, see <http://www.gnu.org/licenses/>.
=end

require 'ostruct'
require File.expand_path(File.dirname(__FILE__) + '/common')
load '../bin/sensible-cinema'

module SensibleSwing
  describe MainWindow do

    it "should be able to start up" do
      MainWindow.new.dispose# shouldn't crash :)
    end

    it "should auto-select a EDL if it matches a DVD's title" do
      MainWindow.new.single_edit_list_matches_dvd("19d121ae8dc40cdd70b57ab7e8c74f76").should_not be nil
    end

    it "should not auto-select if you pass it nil" do
      MainWindow.new.single_edit_list_matches_dvd(nil).should be nil
    end
    
    it "should not die if you choose a poorly formed edl" do
      time_through = 0
      @subject.stub!(:single_edit_list_matches_dvd) {
        'fake filename doesnt even matter because we fake the parsing of it later'
      }
      
      @subject.stub!(:parse_edl) {
        if time_through == 0
          time_through += 1
          eval("a-----") # throws Syntax Error first time
        else
          "stuff"
        end
      }
      @subject.choose_dvd_and_edl_for_it
      @show_blocking_message_dialog_last_args.should_not be nil
    end
    
    it "should not select a file if poorly formed" do
      @subject.stub!(:parse_edl) {
        eval("a----")
      }
      @subject.single_edit_list_matches_dvd 'fake md5'
    end
    
    def with_clean_edl_dir_as this
      FileUtils.rm_rf 'temp'
      Dir.mkdir 'temp'
      old_edl = MainWindow::EDL_DIR
      MainWindow.const_set(:EDL_DIR, 'temp')
      begin
        yield
      ensure
        MainWindow.const_set(:EDL_DIR, old_edl)
      end
    end
    
    it "should prompt if two EDL's match a DVD title" do
      with_clean_edl_dir_as 'temp' do
        MainWindow.new.single_edit_list_matches_dvd("BOBS_BIG_PLAN").should be nil
        Dir.chdir 'temp' do
          File.binwrite('a.txt', "\"disk_unique_id\" => \"abcdef1234\"")
          File.binwrite('b.txt', "\"disk_unique_id\" => \"abcdef1234\"")
        end
        MainWindow.new.single_edit_list_matches_dvd("abcdef1234").should be nil
      end
    end

    it "should modify path to have mencoder available" do
      ENV['PATH'].should include("mencoder")
    end
    
    it "should not modify path to have mplayer available" do
      ENV['PATH'].should_not include("mplayer")
    end
    
    before do
      @subject = MainWindow.new
      @subject.stub!(:choose_dvd_drive) {
        ["mock_dvd_drive", "Volume", "19d121ae8dc40cdd70b57ab7e8c74f76"] # happiest baby on the block
      }
      @subject.stub!(:get_mencoder_commands) { |*args|
        args[-5].should match(/abc/)
        @args = args
        'fake get_mencoder_commands'
      }
      @subject.stub!(:new_filechooser) {
        FakeFileChooser.new
      }
      @subject.stub!(:get_drive_with_most_space_with_slash) {
        "e:\\"
      }
      @subject.stub!(:show_blocking_message_dialog) { |*args|
        @show_blocking_message_dialog_last_args = args
      }
      @subject.stub!(:get_user_input) {'01:00'}
      @subject.stub!(:system_blocking) { |command|
        @system_blocking_command = command
      }

      @subject.stub!(:system_non_blocking) { |command|
        @command = command
        Thread.new {} # fake out the return...
      }
      @subject.stub!(:open_file_to_edit_it) {}
    end
    
    after do
      @subject.background_thread.join if @subject.background_thread
    end

    class FakeFileChooser
      def set_title x; end
      def set_file y; end
      def go
        'abc'
      end
    end
    
    # name like :@rerun_previous
    def click_button(name)
      @subject.instance_variable_get(name).simulate_click
    end

    it "should be able to do a normal copy to hard drive, edited" do
      @subject.system_non_blocking "ls"
      @subject.do_copy_dvd_to_hard_drive(false).should == [false, "abc.fulli_unedited.tmp.mpg"]
      File.exist?('test_file_to_see_if_we_have_permission_to_write_to_this_folder').should be false
    end
    
    it "should have a good default title of 1" do
     @subject.get_title_track({}).should == "1"
     descriptors = {"dvd_title_track" => "3"}
     @subject.get_title_track(descriptors).should == "3"
    end
    
    it "should call through to explorer for the full thing" do
      PlayAudio.stub!(:play) {
        @played = true
      }
      @subject.do_copy_dvd_to_hard_drive(false)
      @subject.background_thread.join
      @args[-4].should == nil
      @system_blocking_command.should match /explorer/
      @system_blocking_command.should_not match /fulli/
      @played.should == true
    end
    
    it "should be able to return the fulli name if it already exists" do
      FileUtils.touch "abc.fulli_unedited.tmp.mpg.done"
      @subject.do_copy_dvd_to_hard_drive(false,true).should == [true, "abc.fulli_unedited.tmp.mpg"]
      FileUtils.rm "abc.fulli_unedited.tmp.mpg.done"
    end
    
    it "should call explorer eventually, if it has to create the fulli file" do
     @subject.do_copy_dvd_to_hard_drive(true).should == [false, "abc.fulli_unedited.tmp.mpg"]
     join_background_thread
     @args[-2].should == 1
     @args[-3].should == "01:00"
     @command.should match /smplayer/
     @command.should_not match /fulli/
    end

    def prompt_for_start_and_end_times
      click_button(:@preview_section)
      join_background_thread
      @args[-2].should == 1
      @args[-3].should == "01:00"
      @command.should match /smplayer/
    end

    it "should prompt for start and end times" do
      prompt_for_start_and_end_times
    end
    
    temp_dir = Dir.tmpdir
    
    def join_background_thread
      @subject.background_thread.join # must be running...
    end
    
    it "should be able to preview unedited" do
      @subject.stub!(:get_user_input).and_return('06:00', '07:00')
      @subject.unstub!(:get_mencoder_commands)
      click_button(:@preview_section_unedited)
      join_background_thread
      temp_file = temp_dir + '/vlc.temp.bat'
      File.read(temp_file).should include("59.99")
    end
    
    it "should be able to rerun the latest start and end times with the rerun button" do
      prompt_for_start_and_end_times
      old_args = @args
      old_args.should_not == nil
      @args = nil
      click_button(:@rerun_preview).join
      @args.should == old_args
      @command.should match(/smplayer/)
    end
    
    it "should warn if you watch an edited time frame with no edits in it" do
      @subject.unstub!(:get_mencoder_commands)
      click_button(:@preview_section)
      @show_blocking_message_dialog_last_args[0].should =~ /unable to/
      @subject.stub!(:get_user_input).and_return('06:00', '07:00')
      # rspec bug: wrong'ish backtrace: proc { prompt_for_start_and_end_times #}.should_not raise_error LODO
      click_button(:@preview_section)
      join_background_thread
      @system_blocking_command.should == "echo wrote (probably successfully) to abc.avi"
    end
    
    it "if the .done files exists, watch unedited should call smplayer ja" do
      FileUtils.touch "abc.fulli_unedited.tmp.mpg.done"
      @subject.instance_variable_get(:@watch_unedited).simulate_click
      @command.should == "smplayer abc.fulli_unedited.tmp.mpg"
      FileUtils.rm "abc.fulli_unedited.tmp.mpg.done"
    end
    
    it "if the .done file does not exist, watch unedited should call smplayer after x seconds" do
      @subject.stub!(:sleep) {
        @slept = true
      } # speed this test up...
      @subject.unstub!(:get_mencoder_commands)
      click_button(:@watch_unedited).join
      join_background_thread
      @system_blocking_command.should_not == nil
      @slept.should == true
      @show_blocking_message_dialog_last_args.should == nil
    end
    
    it "should create a new file for ya" do
      out = MainWindow::EDL_DIR + "/sweetest_disc_ever.txt"
      File.exist?( out ).should be_false
      @subject.stub!(:get_user_input) {'sweetest disc ever'}
      @subject.instance_variable_get(:@create_new_edl_for_current_dvd).simulate_click
      begin
        File.exist?( out ).should be_true
        content = File.read(out)
        content.should_not include("\"title\"")
        content.should include("disk_unique_id")
        content.should include("dvd_title_track")
      ensure
        FileUtils.rm_rf out
      end
    end
    
    it "should display unique disc in an input box" do
      @subject.instance_variable_get(:@display_unique).simulate_click.should == "01:00"
    end
    
    it "should create an edl and pass it through to mplayer" do
      click_button(:@mplayer_edl).join
      @system_blocking_command.should match(/mplayer.*-edl/)
      @system_blocking_command.should match(/-dvd-device /)
    end
    
    it "should play edl with elongated mutes" do
      temp_file = temp_dir + '/mplayer.temp.edl'
      click_button(:@mplayer_edl).join
      wrote = File.read(temp_file)
      # normally "378.0 379.1 1\n"
      wrote.should include("380.85 1")
    end
    
    
    def should_allow_for_changing_file corrupt_file = false
       with_clean_edl_dir_as 'temp' do
        File.binwrite('temp/a.txt', "\"disk_unique_id\" => \"abcdef1234\"")
        @subject.stub!(:choose_dvd_drive) {
          ["mock_dvd_drive", "Volume", "abcdef1234"]
        }
        @subject.choose_dvd_and_edl_for_it[4]['mutes'].should == []
        new_file_contents = '"disk_unique_id" => "abcdef1234","mutes"=>["0:33", "0:34"]'
        new_file_contents = '"a syntax error' if corrupt_file
        File.binwrite('temp/a.txt', new_file_contents)
        # it changed!
        @subject.choose_dvd_and_edl_for_it[4]['mutes'].should_not == []
      end
    end
    
    it "should allow for file to change contents while editing it" do
      should_allow_for_changing_file
    end
    
    it "should prompt you if you re-choose, and your file now has a failure in it" do
      @subject.stub(:show_blocking_message_dialog) {
        @got_here = true
        @subject.stub(:parse_edl) { 'pass the second time through' }
      }
      should_allow_for_changing_file true
      @got_here.should == true
    end
    
    it "should only prompt for save to filename once" do
      count = 0
      @subject.stub!(:new_filechooser) {
        count += 1
        FakeFileChooser.new
      }
      @subject.get_save_to_filename 'yo'
      @subject.get_save_to_filename 'yo'
      count.should == 1
    end
    
    describe 'cacheing dvd drive' do
      before do
        DriveInfo.stub!(:get_dvd_drives_as_openstruct) {
          a = OpenStruct.new
          # NB no VolumeName set
          a.Name = 'a name'
          [a] 
        }
        @subject.unstub!(:choose_dvd_drive)
      end
      
      it "should only prompt for drive once" do
        count = 0
        DriveInfo.stub!(:md5sum_disk) {
          raise if count == 1
          count = 1
          '19d121ae8dc40cdd70b57ab7e8c74f76'
        }
        @subject.choose_dvd_and_edl_for_it
        @subject.choose_dvd_and_edl_for_it
        count.should == 1
      end
  
      it "should prompt you if you need to insert a dvd" do
        proc {@subject.choose_dvd_drive }.should raise_error(/might not yet have.*in it/)
        @show_blocking_message_dialog_last_args.should_not be nil
      end
    end
    
    it "should not show the normal buttons in create mode" do
      MainWindow.new.buttons.length.should == 3 # exit button, two normal buttons
      ARGV << "--create-mode"
      MainWindow.new.buttons.length.should == 9
      ARGV.pop # test cleanup--why not :)
    end
    
  end
  
end
