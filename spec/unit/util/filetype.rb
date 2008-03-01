#!/usr/bin/env ruby

require File.dirname(__FILE__) + '/../../spec_helper'

require 'puppet/type'
require 'puppet/type/filebucket'
require 'puppet/util/filetype'

class Puppet::Util::FileType
    newfiletype(:test_generic) do
        def read; end
        def write(text); end
        def remove; end
    end

    newfiletype(:test_nil_read) do
        def read; nil; end
        def write(text); end
        def remove; end
    end

    newfiletype(:test_header) do
        def read
            return <<-DATA
              # HEADER: This file was autogenerated at Tue Feb 12 15:02:32 -0500 2008 by puppet.
              # HEADER: While it can still be managed manually, it is definitely not recommended.
              # HEADER: Note particularly that the comments starting with 'Puppet Name' should
              # HEADER: not be deleted, as doing so could cause duplicate cron jobs.
              # Puppet Name: reposync
              DATA
        end

        def write(text); end
        def remove; end
    end
end

describe Puppet::Util::FileType do
    include PuppetTest
    FILETYPES = [:flat, :ram, :crontab, :suntab, :netinfo]

    before :each do
        @path = tempfile
    end

    FILETYPES.each do |t|
        it "should support #{t} file types" do
            type = Puppet::Util::FileType.filetype(t).new(@path)
            type.should_not be_nil

            [:read, :write, :remove].each do |m|
                # This doesn't read very well
                Puppet::Util::FileType.filetype(t).new(@path).should be_respond_to(m)
            end
        end
    end

    it "should not backup files that do not yet exist" do
        bucket = Puppet::Type.type(:filebucket)["puppet"]
        bucket.expects(:backup).never

        flatfile = Puppet::Util::FileType.filetype(:flat).new(@path)
        flatfile.backup
    end

    it "should have a default filebucket named 'puppet' that is automatically created" do
        Puppet::Type.type(:filebucket).bucket("puppet").should be_nil

        #This creates the bucket
        bucket = Puppet::Util::FileType.filetype(:flat).new(@path).bucket
        bucket.should_not be_nil

        # The default bucket is 'puppet'
        bucket.should == Puppet::Type.type(:filebucket).bucket("puppet")
    end

    # Someone needs to explain to me why mocha thinks 'mkdefaultbucket' is getting 
    # called once after the expectation initialization.
    #it "will use the default bucket if it already exists" do
    #   Puppet::Type.type(:filebucket)["puppet"].should be_nil
    #   Puppet::Type.type(:filebucket).mkdefaultbucket
    #   Puppet::Type.type(:filebucket)["puppet"].should_not be_nil
    #   Puppet::Type.type(:filebucket).expects(:mkdefaultbucket).never
    #   Puppet::Util::FileType.filetype(:flat).new(@path).bucket
    #end

    it "will create a bucket upon backup if needed" do
        Puppet::Type.type(:filebucket).bucket("puppet").should be_nil

        # The backup won't happen unless the file exists
        File.open(@path, "w") {|f| f.puts "creating the file"}

        flatfile = Puppet::Util::FileType.filetype(:flat).new(@path)

        # Previously the test::unit version of this test was actually
        # performing a backup.  That code should be tested elsewhere.
        default_bucket = mock
        bucket = mock
        default_bucket.expects(:bucket).returns(bucket)
        bucket.expects(:backup).with(@path)
        Puppet::Type.type(:filebucket).expects(:mkdefaultbucket).returns(default_bucket)

        flatfile.backup
    end
    
    it "should backup all files before modifying them" do
        bucket = Puppet::Type.type(:filebucket)["puppet"]

        File.open(@path, "w") { |f| f.print 'yay' }

        flatfile = Puppet::Util::FileType.filetype(:flat).new(@path)
        bucket.expects(:backup).at_most_once
        flatfile.write("something")

        File.read(@path).should == "something"
    end
end

describe Puppet::Util::FileType, "when creating a new type" do
    include PuppetTest

    before :each do
        @path = tempfile
        @generic_type = Puppet::Util::FileType.filetype(:test_generic).new(@path)
        @type_with_header = Puppet::Util::FileType.filetype(:test_header).new(@path)
        @type_with_nil_read = Puppet::Util::FileType.filetype(:test_nil_read).new(@path)
    end

    it "should have a path" do
       @generic_type.path.should == @path
    end

    it "must define the methods read and write" do
        [:read, :write].each do |m|
            lambda do
                Puppet::Util::FileType.newfiletype(:"only_#{m}_defined") do
                    instance_eval(%{def #{m}; end})
                end
            end.should raise_error(NameError)
        end
    end

    it "should automagically record the time the file was loaded" do 
        time_before_load = Time.now
        @generic_type.read
        @generic_type.loaded.should >= time_before_load
    end

    it "should automagically record the time the file was synced" do
        time_before_sync = Time.now
        @generic_type.write
        @generic_type.synced.should >= time_before_sync
    end

    it "should automagically remove the HEADER lines from the file" do
        text = @type_with_header.read
        text.should_not =~ /HEADER/
        text.should =~ /reposync/
    end

    it "should return an empty string instead of nil when reading a file" do
        text = @type_with_nil_read.read
        text.should be_empty
    end
end

describe Puppet::Util::FileType, "When using the flatfile type" do
    include PuppetTest

    before :each do
        @path = tempfile
    end

    it "should sync the changes to the filesystem" do
        text = "This is some text\n"

        flatfile = Puppet::Util::FileType.filetype(:flat).new(@path)
        flatfile.write(text)
        File.read(@path).should == text

        File.open(@path, "w") { |f| f.puts "untracked modification" }
        File.read(@path).should_not == text

        flatfile.write(text)
        File.read(@path).should == text
        flatfile.read.should == text
    end
end
