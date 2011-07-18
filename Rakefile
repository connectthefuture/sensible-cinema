require 'jeweler'
require 'os'

ENV['PATH'] = "C:\\Program Files (x86)\\Git\\cmd;" + ENV['PATH'] # for jeweler's git gem hackaround...

Jeweler::Tasks.new do |s|
    s.name = "sensible-cinema"
    s.summary = "an EDL scene-selector/bleeper that works with online players like hulu"
    s.email = "rogerdpack@gmail.com"
    s.homepage = "http://github.com/rdp"
    s.authors = ["Roger Pack"]
    s.add_dependency 'os', '>= 0.9.3'
    s.add_dependency 'sane', '>= 0.22.0'
    s.add_dependency 'rdp-win32screenshot', '>= 0.0.7.3'
    s.add_dependency 'mini_magick', '>= 3.1' # for ocr...
    s.add_dependency 'whichr', '>= 0.3.6'
    s.add_dependency 'jruby-win32ole'
    s.add_dependency 'rdp-ruby-wmi' # windows
    s.add_dependency 'plist' # mac
    s.add_dependency 'ffi' # mouse, etc. needed at least for MRI
    s.files.exclude '**/*.exe', '**/*.wav', '**/images/*'
    s.add_development_dependency 'hitimes' # now jruby compat!
    s.add_development_dependency 'rspec', '> 2'
    s.add_development_dependency 'jeweler'
    s.add_development_dependency 'rake'
    
    # add as real dependencies for now, as gem install --development is still broken for jruby, basically installing transitive dependencies in error <sigh>

    for gem in s.development_dependencies #['hitimes', 'rspec', 'jeweler', 'rake']
      # bundling rake won't be too expensive, right? and this allows for easier dev setup through gem install
      s.add_dependency gem.name
    end
  end

desc 'run all specs'
task 'spec' do
  failed = []
  Dir.chdir 'spec' do
    for file in Dir['*spec*.rb'] do
      puts "Running " + file
      if !system(OS.ruby_bin + " " + file)
        failed << file
      end
    end
  end
  if failed.length == 0
    p 'all specs passed!' 
  else
    p 'at least one spec failed!', failed
  end
    
end

def get_transitive_dependencies dependencies
  new_dependencies = []
  dependencies.each{|d|
   gem d.name # make sure it's loaded so that it'll be in Gem.loaded_specs
   begin
     dependency_spec = Gem.loaded_specs.select{|name, spec| name == d.name}[0][1]
   rescue
     raise 'possibly dont have that gem are you running jruby for sure?' + d.name
   end
   transitive_deps = dependency_spec.runtime_dependencies
   new_dependencies << transitive_deps
  }
  new_dependencies.flatten.uniq
end

task 'clear_and_copy_vendor_cache' do
   system("rm -rf ../cache.bak")
   system("cp -r vendor/cache ../cache.bak") # for retrieval later
   Dir['vendor/cache/*'].each{|f|
    FileUtils.rm_rf f
    raise 'unable to delete: ' + f if File.exist?(f)
   }
   FileUtils.mkdir_p 'vendor/cache'
end

desc 'collect binary and gem deps for distribution'
task 'rebundle_copy_in_dependencies' => 'gemspec' do
   spec = eval File.read('sensible-cinema.gemspec')
   dependencies = spec.runtime_dependencies
   dependencies = (dependencies + get_transitive_dependencies(dependencies)).uniq
   FileUtils.mkdir_p 'vendor/cache'
   Dir.chdir 'vendor/cache' do
     dependencies.each{|d|
       system("#{OS.ruby_bin} -S gem unpack #{d.name}")
     }
   end
end

desc 'create distro zippable dir'
task 'create_distro_dir' => :gemspec do # depends on gemspec...
  raise 'need rebundle_dependencies first' unless File.directory? 'vendor/cache'
  require 'fileutils'
  spec = eval File.read('sensible-cinema.gemspec')
  dir_out = spec.name + "-" + spec.version.version + '/sensible-cinema'
  FileUtils.rm_rf Dir['sensible-cinema-*'] # remove old versions' distro files
  raise 'unable to delete...' if Dir[spec.name + '-*'].length > 0
  
  existing = Dir['*']
  FileUtils.mkdir_p dir_out
  FileUtils.cp_r(existing, dir_out) # copies files, subdirs in
  # these belong in the parent dir, by themselves.
  FileUtils.cp(Dir["#{dir_out}/template_bats/*.bat"], "#{dir_out}/..")
  FileUtils.cp_r(dir_out + '/template_bats/mac', dir_out)
  p 'created (still need to zip it) ' + dir_out
  FileUtils.rm_rf Dir[dir_out + '/**/{spec}'] # don't need to distribute those..save 3M!
end

def cur_ver
  File.read('VERSION').strip
end

task 'zip' do
  name = 'sensible-cinema-' + cur_ver
  raise unless File.directory? name
  raise unless system("\"c:\\Program Files\\7-Zip\\7z.exe\" a -tzip -r  #{name}.zip #{name}")
  FileUtils.rm_rf name
  p 'created ' + name + '.zip, and deleted its [from] folder'
end

def sys arg
 3.times { |n|
  if n > 0
    p 'retrying ' + arg
  end
  if system arg
    return
  end
 }
 raise arg + ' failed 3x!'
end

task 'deploy' do
  name = 'sensible-cinema-' + cur_ver + ".zip"
  p 'copying to ilab'
  sys "scp #{name} rdp@ilab1.cs.byu.edu:~/incoming"
  p 'creating sf shell'
  sys "ssh rdp@ilab1.cs.byu.edu 'ssh rogerdpack,sensible-cinema@shell.sourceforge.net create'" # needed for the next command to be able to work [weird]
  p 'creating sf dir'
  begin
    sys "ssh rdp@ilab1.cs.byu.edu 'ssh rogerdpack,sensible-cinema@shell.sourceforge.net \"mkdir /home/frs/project/s/se/sensible-cinema/#{cur_ver}\"'"
  rescue => ok_if_dir_already_existing
    puts 'warning--dir already existing?' + ok_if_dir_already_existing.to_s
  end
  p 'copying into sf from ilab'
  sys "ssh rdp@ilab1.cs.byu.edu 'scp ~/incoming/#{name} rogerdpack,sensible-cinema@frs.sourceforge.net:/home/frs/project/s/se/sensible-cinema/#{cur_ver}/#{name}'"
  p 'successfully deployed to sf only! ' + cur_ver
end

task 'gem_release' do
  FileUtils.rm_rf 'pkg'
  Rake::Task["build"].execute
  sys("#{Gem.ruby} -S gem push pkg/sensible-cinema-#{cur_ver}.gem")
  FileUtils.rm_rf 'pkg'
end

desc ' (releases with clean cache dir, which we need now)'
task 'full_release' => [:clear_and_copy_vendor_cache, :rebundle_copy_in_dependencies, :create_distro_dir] do # this is :release
  p 'remember to run all the specs first!'
  raise unless system("git pull")
  raise unless system("git push origin master")
  Rake::Task["gem_release"].execute
  Rake::Task["zip"].execute
  Rake::Task["deploy"].execute
  system(c = "cp -r ../cache.bak/* vendor/cache")
  system("rm -rf ../cache.bak")
end
