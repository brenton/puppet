# Test host job creation, modification, and destruction

if __FILE__ == $0
    $:.unshift '..'
    $:.unshift '../../lib'
    $puppetbase = "../.."
end

require 'puppettest'
require 'puppet'
require 'puppet/type/parsedtype/mount'
require 'test/unit'
require 'facter'

class TestMounts < Test::Unit::TestCase
	include TestPuppet
    def setup
        super
        @mounttype = Puppet.type(:mount)
        @oldfiletype = @mounttype.filetype
    end

    def teardown
        @mounttype.filetype = @oldfiletype
        Puppet.type(:file).clear
        super
    end

    # Here we just create a fake host type that answers to all of the methods
    # but does not modify our actual system.
    def mkfaketype
        pfile = tempfile()
        old = @mounttype.path
        @mounttype.path = pfile

        cleanup do
            @mounttype.path = old
            @mounttype.fileobj = nil
        end

        # Reset this, just in case
        @mounttype.fileobj = nil
    end

    def mkmount
        mount = nil

        if defined? @pcount
            @pcount += 1
        else
            @pcount = 1
        end
        args = {
            :path => "/fspuppet%s" % @pcount,
            :device => "/dev/dsk%s" % @pcount,
        }

        Puppet.type(:mount).fields.each do |field|
            unless args.include? field
                args[field] = "fake%s" % @pcount
            end
        end

        assert_nothing_raised {
            mount = Puppet.type(:mount).create(args)
        }

        return mount
    end

    def test_simplemount
        mkfaketype
        host = nil
        assert_nothing_raised {
            assert_nil(Puppet.type(:mount).retrieve)
        }

        mount = mkmount

        assert_nothing_raised {
            Puppet.type(:mount).store
        }

        assert_nothing_raised {
            assert(
                Puppet.type(:mount).to_file.include?(
                    Puppet.type(:mount).fileobj.read
                ),
                "File does not include all of our objects"
            )
        }
    end

    def test_mountsparse
        assert_nothing_raised {
            @mounttype.retrieve
        }

        # Now just make we've got some mounts we know will be there
        root = @mounttype["/"]
        assert(root, "Could not retrieve root mount")
    end

    def test_rootfs
        fs = nil
        assert_nothing_raised {
            Puppet.type(:mount).retrieve
        }

        assert_nothing_raised {
            fs = Puppet.type(:mount)["/"]
        }
        assert(fs, "Could not retrieve root fs")

        assert_nothing_raised {
            assert(fs.mounted?, "Root is considered not mounted")
        }
    end

    # Make sure it reads and writes correctly.
    def test_readwrite
        assert_nothing_raised {
            Puppet::Type.type(:mount).retrieve
        }

        # Now switch to storing in ram
        mkfaketype

        fs = mkmount

        assert(Puppet::Type.type(:mount).path != "/etc/fstab")

        assert_events([:mount_created], fs)

        text = Puppet::Type.type(:mount).fileobj.read

        assert(text =~ /#{fs[:path]}/, "Text did not include new fs")

        fs[:ensure] = :absent

        assert_events([:mount_removed], fs)
        text = Puppet::Type.type(:mount).fileobj.read

        assert(text !~ /#{fs[:path]}/, "Text still includes new fs")

        fs[:ensure] = :present

        assert_events([:mount_created], fs)

        text = Puppet::Type.type(:mount).fileobj.read

        assert(text =~ /#{fs[:path]}/, "Text did not include new fs")
    end

    if Process.uid == 0
    def test_mountfs
        fs = nil
        case Facter["hostname"].value
        when "culain": fs = "/ubuntu"
        else
            $stderr.puts "No mount for mount testing; skipping"
            return
        end

        backup = tempfile()

        FileUtils.cp(Puppet::Type.type(:mount).path, backup)

        # Make sure the original gets reinstalled.
        cleanup do 
            FileUtils.cp(backup, Puppet::Type.type(:mount).path)
        end

        Puppet.type(:mount).retrieve

        obj = Puppet.type(:mount)[fs]

        assert(obj, "Could not retrieve %s object" % fs)

        current = nil

        assert_nothing_raised {
            current = obj.mounted?
        }

        if current
            # Make sure the original gets reinstalled.
            cleanup do
                unless obj.mounted?
                    obj.mount
                end
            end
        end

        unless current
            assert_nothing_raised {
                obj.mount
            }
        end

        # Now copy all of the states' "is" values to the "should" values
        obj.each do |state|
            state.should = state.is
        end

        # Verify we can remove the mount
        assert_nothing_raised {
            obj[:ensure] = :absent
        }

        assert_events([:mount_removed], obj)

        # And verify it's gone
        assert(!obj.mounted?, "Object is mounted after being removed")

        text = Puppet.type(:mount).fileobj.read

        assert(text !~ /#{fs}/,
            "Fstab still contains %s" % fs)

        assert_raise(Puppet::Error, "Removed mount did not throw an error") {
            obj.mount
        }

        assert_nothing_raised {
            obj[:ensure] = :present
        }

        assert_events([:mount_created], obj)

        assert(File.read(Puppet.type(:mount).path) =~ /#{fs}/,
            "Fstab does not contain %s" % fs)

        assert(! obj.mounted?, "Object is mounted incorrectly")

        assert_nothing_raised {
            obj[:ensure] = :mounted
        }

        assert_events([:mount_mounted], obj)

        assert(File.read(Puppet.type(:mount).path) =~ /#{fs}/,
            "Fstab does not contain %s" % fs)

        assert(obj.mounted?, "Object is not mounted")

        unless current
            assert_nothing_raised {
                obj.unmount
            }
        end
    end
    end
end

# $Id$