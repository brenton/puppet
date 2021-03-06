#!/usr/bin/env ruby

require File.dirname(__FILE__) + '/../../../lib/puppettest'

require 'puppettest'
require 'puppettest/support/utils'
require 'fileutils'

class TestFileTarget < Test::Unit::TestCase
    include PuppetTest::Support::Utils
    include PuppetTest::FileTesting

    def setup
        super
        @file = Puppet::Type.type(:file)
    end

    # Make sure we can create symlinks
    def test_symlinks
        path = tempfile()
        link = tempfile()

        File.open(path, "w") { |f| f.puts "yay" }

        file = nil
        assert_nothing_raised {
            file = Puppet.type(:file).create(
                :title => "somethingelse",
                :ensure => path,
                :path => link
            )
        }

        assert_events([:link_created], file)

        assert(FileTest.symlink?(link), "Link was not created")

        assert_equal(path, File.readlink(link), "Link was created incorrectly")

        # Make sure running it again works
        assert_events([], file)
        assert_events([], file)
        assert_events([], file)
    end
    
    def test_linkrecurse
        dest = tempfile()
        link = @file.create :path => tempfile(), :recurse => true, :ensure => dest
        mk_catalog link
        
        ret = nil
        
        # Start with nothing, just to make sure we get nothing back
        assert_nothing_raised { ret = link.linkrecurse(true) }
        assert_nil(ret, "got a return when the dest doesn't exist")
        
        # then with a directory with only one file
        Dir.mkdir(dest)
        one = File.join(dest, "one")
        File.open(one, "w") { |f| f.puts "" }
        link[:ensure] = dest
        assert_nothing_raised { ret = link.linkrecurse(true) }
        
        assert_equal(:directory, link.should(:ensure), "ensure was not set to directory")
        assert_equal([File.join(link.title, "one")], ret.collect { |f| f.title },
            "Did not get linked file")
        oneobj = @file[File.join(link.title, "one")]
        assert_equal(one, oneobj.should(:target), "target was not set correctly")
        
        oneobj.remove
        File.unlink(one)
        
        # Then make sure we get multiple files
        returns = []
        5.times do |i|
            path = File.join(dest, i.to_s)
            returns << File.join(link.title, i.to_s)
            File.open(path, "w") { |f| f.puts "" }
        end
        assert_nothing_raised { ret = link.linkrecurse(true) }

        assert_equal(returns.sort, ret.collect { |f| f.title }.sort,
            "Did not get links back")
        
        returns.each do |path|
            obj = @file[path]
            assert(path, "did not get obj for %s" % path)
            sdest = File.join(dest, File.basename(path))
            assert_equal(sdest, obj.should(:target),
                "target was not set correctly for %s" % path)
        end
    end

    def test_simplerecursivelinking
        source = tempfile()
        path = tempfile()
        subdir = File.join(source, "subdir")
        file = File.join(subdir, "file")

        system("mkdir -p %s" % subdir)
        system("touch %s" % file)

        link = nil
        assert_nothing_raised {
            link = Puppet.type(:file).create(
                :ensure => source,
                :path => path,
                :recurse => true
            )
        }

        assert_apply(link)

        sublink = File.join(path, "subdir")
        linkpath = File.join(sublink, "file")
        assert(File.directory?(path), "dest is not a dir")
        assert(File.directory?(sublink), "subdest is not a dir")
        assert(File.symlink?(linkpath), "path is not a link")
        assert_equal(file, File.readlink(linkpath))

        assert_nil(@file[sublink], "objects were not removed")
        assert_equal([], link.evaluate, "Link is not in sync")
    end

    def test_recursivelinking
        source = tempfile()
        dest = tempfile()

        files = []
        dirs = []

        # Make a bunch of files and dirs
        Dir.mkdir(source)
        Dir.chdir(source) do
            system("mkdir -p %s" % "some/path/of/dirs")
            system("mkdir -p %s" % "other/path/of/dirs")
            system("touch %s" % "file")
            system("touch %s" % "other/file")
            system("touch %s" % "some/path/of/file")
            system("touch %s" % "some/path/of/dirs/file")
            system("touch %s" % "other/path/of/file")

            files = %x{find . -type f}.chomp.split(/\n/)
            dirs = %x{find . -type d}.chomp.split(/\n/).reject{|d| d =~ /^\.+$/ }
        end

        link = nil
        assert_nothing_raised {
            link = Puppet.type(:file).create(
                :ensure => source,
                :path => dest,
                :recurse => true
            )
        }

        assert_apply(link)

        files.each do |f|
            f.sub!(/^\.#{File::SEPARATOR}/, '')
            path = File.join(dest, f)
            assert(FileTest.exists?(path), "Link %s was not created" % path)
            assert(FileTest.symlink?(path), "%s is not a link" % f)
            target = File.readlink(path)
            assert_equal(File.join(source, f), target)
        end

        dirs.each do |d|
            d.sub!(/^\.#{File::SEPARATOR}/, '')
            path = File.join(dest, d)
            assert(FileTest.exists?(path), "Dir %s was not created" % path)
            assert(FileTest.directory?(path), "%s is not a directory" % d)
        end
    end

    def test_localrelativelinks
        dir = tempfile()
        Dir.mkdir(dir)
        source = File.join(dir, "source")
        File.open(source, "w") { |f| f.puts "yay" }
        dest = File.join(dir, "link")

        link = nil
        assert_nothing_raised {
            link = Puppet.type(:file).create(
                :path => dest,
                :ensure => "source"
            )
        }

        assert_events([:link_created], link)
        assert(FileTest.symlink?(dest), "Did not create link")
        assert_equal("source", File.readlink(dest))
        assert_equal("yay\n", File.read(dest))
    end

    def test_recursivelinkingmissingtarget
        source = tempfile()
        dest = tempfile()

        objects = []
        objects << Puppet.type(:exec).create(
            :command => "mkdir %s; touch %s/file" % [source, source],
            :title => "yay",
            :path => ENV["PATH"]
        )
        objects << Puppet.type(:file).create(
            :ensure => source,
            :path => dest,
            :recurse => true,
            :require => objects[0]
        )

        assert_apply(*objects)

        link = File.join(dest, "file")
        assert(FileTest.symlink?(link), "Did not make link")
        assert_equal(File.join(source, "file"), File.readlink(link))
    end

    def test_insync?
        source = tempfile()
        dest = tempfile()

        obj = @file.create(:path => source, :target => dest)

        prop = obj.send(:property, :target)
        prop.send(:instance_variable_set, "@should", [:nochange])
        assert(prop.insync?(prop.retrieve),
            "Property not in sync with should == :nochange")

        prop = obj.send(:property, :target)
        prop.send(:instance_variable_set, "@should", [:notlink])
        assert(prop.insync?(prop.retrieve),
            "Property not in sync with should == :nochange")

        # Lastly, make sure that we don't try to do anything when we're
        # recursing, since 'ensure' does the work.
        obj[:recurse] = true
        prop.should = dest
        assert(prop.insync?(prop.retrieve),
            "Still out of sync during recursion")
    end

    def test_replacedirwithlink
        Puppet[:trace] = false
        path = tempfile()
        link = tempfile()

        File.open(path, "w") { |f| f.puts "yay" }
        Dir.mkdir(link)
        File.open(File.join(link, "yay"), "w") do |f| f.puts "boo" end

        file = nil
        assert_nothing_raised {
            file = Puppet.type(:file).create(
                :ensure => path,
                :path => link,
                :backup => false
            )
        }

        # First run through without :force
        assert_events([], file)

        assert(FileTest.directory?(link), "Link replaced dir without force")

        assert_nothing_raised { file[:force] = true }

        assert_events([:link_created], file)

        assert(FileTest.symlink?(link), "Link was not created")

        assert_equal(path, File.readlink(link), "Link was created incorrectly")
    end

    def test_replace_links_with_files
        base = tempfile()

        Dir.mkdir(base)

        file = File.join(base, "file")
        link = File.join(base, "link")
        File.open(file, "w") { |f| f.puts "yayness" }
        File.symlink(file, link)

        obj = Puppet::Type.type(:file).create(
            :path => link,
            :ensure => "file"
        )

        assert_apply(obj)

        assert_equal("yayness\n", File.read(file),
            "Original file got changed")
        assert_equal("file", File.lstat(link).ftype, "File is still a link")
    end

    def test_no_erase_linkedto_files
        base = tempfile()

        Dir.mkdir(base)

        dirs = {}
        %w{other source target}.each do |d|
            dirs[d] = File.join(base, d)
            Dir.mkdir(dirs[d])
        end

        file = File.join(dirs["other"], "file")
        sourcefile = File.join(dirs["source"], "sourcefile")
        link = File.join(dirs["target"], "sourcefile")

        File.open(file, "w") { |f| f.puts "other" }
        File.open(sourcefile, "w") { |f| f.puts "source" }
        File.symlink(file, link)

        obj = Puppet::Type.type(:file).create(
            :path => dirs["target"],
            :ensure => :file,
            :source => dirs["source"],
            :recurse => true
        )
        config = mk_catalog obj
        config.apply

        newfile = File.join(dirs["target"], "sourcefile")

        assert(File.directory?(dirs["target"]), "Dir did not get created")
        assert(File.file?(newfile), "File did not get copied")

        assert_equal(File.read(sourcefile), File.read(newfile),
            "File did not get copied correctly.")

        assert_equal("other\n", File.read(file),
            "Original file got changed")
        assert_equal("file", File.lstat(link).ftype, "File is still a link")
    end

    def test_replace_links
        dest = tempfile()
        otherdest = tempfile()
        link = tempfile()

        File.open(dest, "w") { |f| f.puts "boo" }
        File.open(otherdest, "w") { |f| f.puts "yay" }

        obj = Puppet::Type.type(:file).create(
            :path => link,
            :ensure => otherdest
        )


        assert_apply(obj)

        assert_equal(otherdest, File.readlink(link), "Link did not get created")

        obj[:ensure] = dest

        assert_apply(obj)

        assert_equal(dest, File.readlink(link), "Link did not get changed")
    end
end

