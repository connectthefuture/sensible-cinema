require File.dirname(__FILE__) + '/common'
require_relative '/../lib/keyboard_input'

describe KeyboardInput do

  class Go
    @time = 58
    def self.cur_time
      @time += 1
    end
    
    def self.got
      @got
    end
    
    def self.keyboard_input input
      @got = input
    end
  end

  before do
    @a = KeyboardInput.new Go
  end
  
  it "should display minutes and seconds" do
    @a.get_line_printout.should include("0:59")
    @a.get_line_printout.should include("1:00")    
  end
  
  it "should translate keys to characters" do
    @a.handle_keystroke 77
    Go.got.should == "M"
    @a.handle_keystroke 109
    Go.got.should == "m"
  end  
  
end
