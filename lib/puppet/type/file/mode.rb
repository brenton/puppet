# Manage file modes.  This state should support different formats
# for specification (e.g., u+rwx, or -0011), but for now only supports
# specifying the full mode.
module Puppet
    Puppet.type(:file).newproperty(:mode) do
        require 'etc'
        desc "Mode the file should be.  Currently relatively limited:
            you must specify the exact mode the file should be."
        @event = :file_changed

        # Our modes are octal, so make sure they print correctly.  Other
        # valid values are symbols, basically
        def is_to_s(currentvalue)
            case currentvalue
            when Integer
                return "%o" % currentvalue
            when Symbol
                return currentvalue
            else
                raise Puppet::DevError, "Invalid current value for mode: %s" %
                    currentvalue.inspect
            end
        end

        def should_to_s(newvalue = @should)
            case newvalue
            when Integer
                return "%o" % newvalue
            when Symbol
                return newvalue
            else
                raise Puppet::DevError, "Invalid 'should' value for mode: %s" %
                    newvalue.inspect
            end
        end

        munge do |should|
            # this is pretty hackish, but i need to make sure the number is in
            # octal, yet the number can only be specified as a string right now
            value = should
            if value.is_a?(String)
                unless value =~ /^\d+$/
                    raise Puppet::Error, "File modes can only be numbers, not %s" %
                        value.inspect
                end
                # Make sure our number looks like octal.
                unless value =~ /^0/
                    value = "0" + value
                end
                old = value
                begin
                    value = Integer(value)
                rescue ArgumentError => detail
                    raise Puppet::DevError, "Could not convert %s to integer" %
                        old.inspect
                end
            end

            return value
        end

        # If we're a directory, we need to be executable for all cases
        # that are readable.  This should probably be selectable, but eh.
        def dirmask(value)
            if FileTest.directory?(@resource[:path])
                if value & 0400 != 0
                    value |= 0100
                end
                if value & 040 != 0
                    value |= 010
                end
                if value & 04 != 0
                    value |= 01
                end
            end

            return value
        end

        def insync?(currentvalue)
            if stat = @resource.stat and stat.ftype == "link" and @resource[:links] != :follow
                self.debug "Not managing symlink mode"
                return true
            else
                return super(currentvalue)
            end
        end

        def retrieve
            # If we're not following links and we're a link, then we just turn
            # off mode management entirely.

            if stat = @resource.stat(false)
                unless defined? @fixed
                    if defined? @should and @should
                        @should = @should.collect { |s| self.dirmask(s) }
                    end
                end
                return stat.mode & 007777
            else
                return :absent
            end
        end

        def sync
            unless @resource.stat(false)
                stat = @resource.stat(true)

                unless stat
                    self.debug "File does not exist; cannot set mode"
                    return nil
                end
            end

            mode = self.should

            if mode == :absent
                # This is really only valid for create states...
                return nil
            end

            begin
                File.chmod(mode, @resource[:path])
            rescue => detail
                error = Puppet::Error.new("failed to chmod %s: %s" %
                    [@resource[:path], detail.message])
                error.set_backtrace detail.backtrace
                raise error
            end
            return :file_changed
        end
    end
end

