#!/usr/bin/env ruby

$:.unshift("../../lib") if __FILE__ =~ /\.rb$/

require 'puppettest'
require 'etc'

class TestUser < Test::Unit::TestCase
	include PuppetTest

    p = Puppet::Type.type(:user).provide :fake, :parent => PuppetTest::FakeProvider do
        @name = :fake
        apimethods
        def create
            @ensure = :present
            @model.eachproperty do |property|
                next if property.name == :ensure
                property.sync
            end
        end

        def delete
            @ensure = :absent
            @model.eachproperty do |property|
                send(property.name.to_s + "=", :absent)
            end
        end

        def exists?
            if defined? @ensure and @ensure == :present
                true
            else
                false
            end
        end
    end

    FakeUserProvider = p

    @@fakeproviders[:group] = p

    def findshell(old = nil)
        %w{/bin/sh /bin/bash /sbin/sh /bin/ksh /bin/zsh /bin/csh /bin/tcsh
            /usr/bin/sh /usr/bin/bash /usr/bin/ksh /usr/bin/zsh /usr/bin/csh
            /usr/bin/tcsh}.find { |shell|
                if old
                    FileTest.exists?(shell) and shell != old
                else
                    FileTest.exists?(shell)
                end
        }
    end

    def setup
        super
        Puppet::Type.type(:user).defaultprovider = FakeUserProvider
    end

    def teardown
        Puppet::Type.type(:user).defaultprovider = nil
        super
    end

    def mkuser(name)
        user = nil
        assert_nothing_raised {
            user = Puppet.type(:user).create(
                :name => name,
                :comment => "Puppet Testing User",
                :gid => Puppet::Util::SUIDManager.gid,
                :shell => findshell(),
                :home => "/home/%s" % name
            )
        }

        assert(user, "Did not create user")

        return user
    end

    def attrtest_ensure(user)
        old = user.provider.ensure
        user[:ensure] = :absent

        comp = newcomp("ensuretest", user)
        assert_apply(user)
        assert(!user.provider.exists?, "User is still present")
        user[:ensure] = :present
        assert_events([:user_created], comp)
        assert(user.provider.exists?, "User is absent")
        user[:ensure] = :absent
        trans = assert_events([:user_removed], comp)

        assert_rollback_events(trans, [:user_created], "user")

        user[:ensure] = old
        assert_apply(user)
    end

    def attrtest_comment(user)
        user.retrieve
        old = user.provider.comment
        user[:comment] = "A different comment"

        comp = newcomp("commenttest", user)

        trans = assert_events([:user_changed], comp, "user")

        assert_equal("A different comment", user.provider.comment,
            "Comment was not changed")

        assert_rollback_events(trans, [:user_changed], "user")

        assert_equal(old, user.provider.comment,
            "Comment was not reverted")
    end

    def attrtest_home(user)
        obj = nil
        comp = newcomp("hometest", user)

        old = user.provider.home
        user[:home] = old

        trans = assert_events([], comp, "user")

        user[:home] = "/tmp"

        trans = assert_events([:user_changed], comp, "user")

        assert_equal("/tmp", user.provider.home, "Home was not changed")

        assert_rollback_events(trans, [:user_changed], "user")

        assert_equal(old, user.provider.home, "Home was not reverted")
    end

    def attrtest_shell(user)
        old = user.provider.shell
        comp = newcomp("shelltest", user)

        user[:shell] = old

        trans = assert_events([], comp, "user")

        newshell = findshell(old)

        unless newshell
            $stderr.puts "Cannot find alternate shell; skipping shell test"
            return
        end

        user[:shell] = newshell

        trans = assert_events([:user_changed], comp, "user")

        user.retrieve
        assert_equal(newshell, user.provider.shell,
            "Shell was not changed")

        assert_rollback_events(trans, [:user_changed], "user")
        user.retrieve

        assert_equal(old, user.provider.shell, "Shell was not reverted")
    end

    def attrtest_gid(user)
        obj = nil
        old = user.provider.gid
        comp = newcomp("gidtest", user)

        user.retrieve

        user[:gid] = old

        trans = assert_events([], comp, "user")

        newgid = %w{nogroup nobody staff users daemon}.find { |gid|
                begin
                    group = Etc.getgrnam(gid)
                rescue ArgumentError => detail
                    next
                end
                old != group.gid and group.gid > 0
        }

        unless newgid
            $stderr.puts "Cannot find alternate group; skipping gid test"
            return
        end

        # first test by name
        assert_nothing_raised("Failed to specify group by name") {
            user[:gid] = newgid
        }

        trans = assert_events([:user_changed], comp, "user")

        # then by id
        newgid = Etc.getgrnam(newgid).gid

        assert_nothing_raised("Failed to specify group by id for %s" % newgid) {
            user[:gid] = newgid
        }

        user.retrieve

        assert_events([], comp, "user")

        assert_equal(newgid, user.provider.gid, "GID was not changed")

        assert_rollback_events(trans, [:user_changed], "user")

        assert_equal(old, user.provider.gid, "GID was not reverted")
    end

    def attrtest_uid(user)
        obj = nil
        comp = newcomp("uidtest", user)

        user.provider.uid = 1

        old = 1
        newuid = 1
        while true
            newuid += 1

            if newuid - old > 1000
                $stderr.puts "Could not find extra test UID"
                return
            end
            begin
                newuser = Etc.getpwuid(newuid)
            rescue ArgumentError => detail
                break
            end
        end

        assert_nothing_raised("Failed to change user id") {
            user[:uid] = newuid
        }

        trans = assert_events([:user_changed], comp, "user")

        assert_equal(newuid, user.provider.uid, "UID was not changed")

        assert_rollback_events(trans, [:user_changed], "user")

        assert_equal(old, user.provider.uid, "UID was not reverted")
    end

    def attrtest_groups(user)
        Etc.setgrent
        max = 0
        while group = Etc.getgrent
            if group.gid > max and group.gid < 5000
                max = group.gid
            end
        end

        groups = []
        main = []
        extra = []
        5.times do |i|
            i += 1
            name = "pptstgr%s" % i
            groups << name
            if i < 3
                main << name
            else
                extra << name
            end
        end

        assert(user[:membership] == :minimum, "Membership did not default correctly")

        assert_nothing_raised {
            user.retrieve
        }

        # Now add some of them to our user
        assert_nothing_raised {
            user[:groups] = extra
        }
        assert_nothing_raised {
            user.retrieve
        }

        assert_instance_of(String, user.property(:groups).should)

        # Some tests to verify that groups work correctly startig from nothing
        # Remove our user
        user[:ensure] = :absent
        assert_apply(user)

        assert_nothing_raised do
            user.retrieve
        end

        # And add it again
        user[:ensure] = :present
        assert_apply(user)

        # Make sure that the groups are a string, not an array
        assert(user.provider.groups.is_a?(String),
            "Incorrectly passed an array to groups")

        user.retrieve

        assert(user.property(:groups).is, "Did not retrieve group list")

        list = user.property(:groups).is
        assert_equal(extra.sort, list.sort, "Group list is not equal")

        # Now set to our main list of groups
        assert_nothing_raised {
            user[:groups] = main
        }

        assert_equal((main + extra).sort, user.property(:groups).should.split(",").sort)

        assert_nothing_raised {
            user.retrieve
        }

        assert(!user.insync?, "User is incorrectly in sync")

        assert_apply(user)

        assert_nothing_raised {
            user.retrieve
        }

        # We're not managing inclusively, so it should keep the old group
        # memberships and add the new ones
        list = user.property(:groups).is
        assert_equal((main + extra).sort, list.sort, "Group list is not equal")

        assert_nothing_raised {
            user[:membership] = :inclusive
        }
        assert_nothing_raised {
            user.retrieve
        }

        assert(!user.insync?, "User is incorrectly in sync")

        assert_events([:user_changed], user)
        assert_nothing_raised {
            user.retrieve
        }

        list = user.property(:groups).is
        assert_equal(main.sort, list.sort, "Group list is not equal")

        # Set the values a bit differently.
        user.property(:groups).should = list.sort { |a,b| b <=> a }
        user.property(:groups).is = list.sort

        assert(user.property(:groups).insync?, "Groups property did not sort groups")

        user.delete(:groups)
    end

    def test_autorequire
        file = tempfile()
        comp = nil
        user = nil
        group =nil
        home = nil
        ogroup = nil
        assert_nothing_raised {
            user = Puppet.type(:user).create(
                :name => "pptestu",
                :home => file,
                :gid => "pptestg",
                :groups => "yayness"
            )
            home = Puppet.type(:file).create(
                :path => file,
                :owner => "pptestu",
                :ensure => "directory"
            )
            group = Puppet.type(:group).create(
                :name => "pptestg"
            )
            ogroup = Puppet.type(:group).create(
                :name => "yayness"
            )
            comp = newcomp(user, group, home, ogroup)
        }
        
        rels = nil
        assert_nothing_raised() { rels = user.autorequire }

        assert(rels.detect { |r| r.source == group }, "User did not require group")
        assert(rels.detect { |r| r.source == ogroup }, "User did not require other groups")
        assert_nothing_raised() { rels = home.autorequire }
        assert(rels.detect { |r| r.source == user }, "Homedir did not require user")
    end

    def test_simpleuser
        name = "pptest"

        user = mkuser(name)

        comp = newcomp("usercomp", user)

        trans = assert_events([:user_created], comp, "user")

        assert_equal(user.should(:comment), user.provider.comment,
            "Comment was not set correctly")

        assert_rollback_events(trans, [:user_removed], "user")

        assert(! user.provider.exists?, "User did not get deleted")
    end

    def test_allusermodelproperties
        user = nil
        name = "pptest"

        user = mkuser(name)

        assert(! user.provider.exists?, "User %s is present" % name)

        comp = newcomp("usercomp", user)

        trans = assert_events([:user_created], comp, "user")

        user.retrieve
        assert_equal("Puppet Testing User", user.provider.comment,
            "Comment was not set")

        tests = Puppet.type(:user).validproperties

        tests.each { |test|
            if self.respond_to?("attrtest_%s" % test)
                self.send("attrtest_%s" % test, user)
            else
                Puppet.err "Not testing attr %s of user" % test
            end
        }

        user[:ensure] = :absent
        assert_apply(user)
    end
    
    # Testing #455
    def test_autorequire_with_no_group_should
        user = Puppet::Type.type(:user).create(:name => "yaytest", :check => :all)
        
        assert_nothing_raised do
            user.autorequire
        end

        user[:ensure] = :absent

        assert_nothing_raised do
            user.evaluate
        end

        assert(user.send(:property, :groups).insync?,
            "Groups state considered out of sync with no :should value")
    end
end

# $Id$