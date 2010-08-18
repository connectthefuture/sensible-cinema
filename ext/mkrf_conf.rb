raise 'must be using jruby to be able to run this...at least for now' unless RUBY_PLATFORM =~ /java/

# reset the cache...
require 'sane'
require_relative '../lib/ocr'
OCR.clear_cache!

f = File.open(File.join(File.dirname(__FILE__), "Rakefile"), "w") # create dummy rakefile to indicate success
f.write("task :default\n")
f.close