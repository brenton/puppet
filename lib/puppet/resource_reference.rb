#
#  Created by Luke Kanies on 2007-11-28.
#  Copyright (c) 2007. All rights reserved.

require 'puppet'

# A simple class to canonize how we refer to and retrieve
# resources.
class Puppet::ResourceReference
    attr_reader :type
    attr_accessor :title, :catalog

    def initialize(type, title)
        # This will set @type if it looks like a resource reference.
        self.title = title

        # Don't override whatever was done by setting the title.
        self.type = type if self.type.nil?
        
        @builtin_type = nil
    end

    # Find our resource.
    def resolve
        if catalog
            return catalog.resource(to_s)
        end
        # If it's builtin, then just ask for it directly from the type.
        if t = builtin_type
            t[@title]
        else # Else, look for a component with the full reference as the name.
            Puppet::Type::Component[to_s]
        end
    end

    # If the title has square brackets, treat it like a reference and
    # set things appropriately; else, just set it.
    def title=(value)
        if value =~ /^([^\[\]]+)\[(.+)\]$/
            self.type = $1
            @title = $2
        else
            @title = value
        end
    end

    # Canonize the type so we know it's always consistent.
    def type=(value)
        if value.nil? or value.to_s.downcase == "component"
            @type = "Class"
        else
            @type = value.to_s.split("::").collect { |s| s.capitalize }.join("::")
        end
    end

    # Convert to the standard way of referring to resources.
    def to_s
        "%s[%s]" % [@type, @title]
    end

    private

    def builtin_type?
        builtin_type ? true : false
    end

    def builtin_type
        if @builtin_type.nil?
            if @type =~ /::/
                @builtin_type = false
            elsif klass = Puppet::Type.type(@type.to_s.downcase)
                @builtin_type = klass
            else
                @builtin_type = false
            end
        end
        @builtin_type
    end
end
