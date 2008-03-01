#!/usr/bin/env ruby

require File.dirname(__FILE__) + '/../lib/puppettest'

require 'puppettest'
require 'puppet/util/filetype'
require 'mocha'

class TestFileType < Test::Unit::TestCase
	include PuppetTest

    def test_backup
        path = tempfile
        type = Puppet::Type.type(:filebucket)

        obj = Puppet::Util::FileType.filetype(:flat).new(path)

        # Then create the file
        File.open(path, "w") { |f| f.print 'one' }

        # Then try it with no filebucket objects
        assert_nothing_raised("Could not call backup with no buckets") do
            obj.backup
        end
        puppet = type["puppet"]
        assert(puppet, "Did not create default filebucket")

        assert_equal("one", puppet.bucket.getfile(Digest::MD5.hexdigest(File.read(path))), "Could not get file from backup")

        # Try it again when the default already exists
        File.open(path, "w") { |f| f.print 'two' }
        assert_nothing_raised("Could not call backup with no buckets") do
            obj.backup
        end

        assert_equal("two", puppet.bucket.getfile(Digest::MD5.hexdigest(File.read(path))), "Could not get file from backup")
    end

    if Facter["operatingsystem"].value == "Darwin"
    def test_ninfotoarray
        obj = nil
        type = nil

        assert_nothing_raised {
            type = Puppet::Util::FileType.filetype(:netinfo)
        }

        assert(type, "Could not retrieve netinfo filetype")
        %w{users groups aliases}.each do |map|
            assert_nothing_raised {
                obj = type.new(map)
            }

            assert_nothing_raised("could not read map %s" % map) {
                obj.read
            }

            array = nil

            assert_nothing_raised("Failed to parse %s map" % map) {
                array = obj.to_array
            }

            assert_instance_of(Array, array)

            array.each do |record|
                assert_instance_of(Hash, record)
                assert(record.length != 0)
            end
        end
    end
    end
end

