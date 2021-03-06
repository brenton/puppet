require 'openssl'
require 'puppet'
require 'puppet/parser/interpreter'
require 'puppet/sslcertificates'
require 'xmlrpc/server'
require 'yaml'

class Puppet::Network::Handler
    class Configuration < Handler
        desc "Puppet's configuration compilation interface.  Passed a node name
            or other key, retrieves information about the node (using the ``node_source``)
            and returns a compiled configuration."

        include Puppet::Util

        attr_accessor :local, :classes

        @interface = XMLRPC::Service::Interface.new("configuration") { |iface|
                iface.add_method("string configuration(string)")
                iface.add_method("string version()")
        }

        # Compile a node's configuration.
        def configuration(key, client = nil, clientip = nil)
            # If we want to use the cert name as our key
            if Puppet[:node_name] == 'cert' and client
                key = client
            end

            # Note that this is reasonable, because either their node source should actually
            # know about the node, or they should be using the ``none`` node source, which
            # will always return data.
            unless node = Puppet::Node.find_by_any_name(key)
                raise Puppet::Error, "Could not find node '%s'" % key
            end

            # Add any external data to the node.
            add_node_data(node)

            configuration = compile(node)

            return translate(configuration)
        end

        def initialize(options = {})
            options.each do |param, value|
                case param
                when :Classes: @classes = value
                when :Local: self.local = value
                else
                    raise ArgumentError, "Configuration handler does not accept %s" % param
                end
            end

            set_server_facts
        end

        # Are we running locally, or are our clients networked?
        def local?
            self.local
        end

        # Return the configuration version.
        def version(client = nil, clientip = nil)
            if client and node = Puppet::Node.find_by_any_name(client)
                update_node_check(node)
                return interpreter.configuration_version(node)
            else
                # Just return something that will always result in a recompile, because
                # this is local.
                return (Time.now + 1000).to_i
            end
        end

        private

        # Add any extra data necessary to the node.
        def add_node_data(node)
            # Merge in our server-side facts, so they can be used during compilation.
            node.merge(@server_facts)

            # Add any specified classes to the node's class list.
            if @classes
                @classes.each do |klass|
                    node.classes << klass
                end
            end
        end

        # Compile the actual configuration.
        def compile(node)
            # Pick the benchmark level.
            if local?
                level = :none
            else
                level = :notice
            end

            # Ask the interpreter to compile the configuration.
            str = "Compiled configuration for %s" % node.name
            if node.environment
                str += " in environment %s" % node.environment
            end
            config = nil
            benchmark(level, "Compiled configuration for %s" % node.name) do
                begin
                    config = interpreter.compile(node)
                rescue => detail
                    # If we're local, then we leave it to the local system
                    # to handle error reporting, but otherwise we do it here
                    # so the interpreter doesn't need to know if the parser
                    # is local or not.
                    Puppet.err(detail.to_s) unless local?
                    raise
                end
            end

            return config
        end

        # Create our interpreter object.
        def create_interpreter
            return Puppet::Parser::Interpreter.new
        end

        # Create/return our interpreter.
        def interpreter
            unless defined?(@interpreter) and @interpreter
                @interpreter = create_interpreter
            end
            @interpreter
        end

        # Initialize our server fact hash; we add these to each client, and they
        # won't change while we're running, so it's safe to cache the values.
        def set_server_facts
            @server_facts = {}

            # Add our server version to the fact list
            @server_facts["serverversion"] = Puppet.version.to_s

            # And then add the server name and IP
            {"servername" => "fqdn",
                "serverip" => "ipaddress"
            }.each do |var, fact|
                if value = Facter.value(fact)
                    @server_facts[var] = value
                else
                    Puppet.warning "Could not retrieve fact %s" % fact
                end
            end

            if @server_facts["servername"].nil?
                host = Facter.value(:hostname)
                if domain = Facter.value(:domain)
                    @server_facts["servername"] = [host, domain].join(".")
                else
                    @server_facts["servername"] = host
                end
            end
        end

        # Translate our configuration appropriately for sending back to a client.
        def translate(config)
            if local?
                config
            else
                CGI.escape(config.to_yaml(:UseBlock => true))
            end
        end

        # Mark that the node has checked in. FIXME this needs to be moved into
        # the Node class, or somewhere that's got abstract backends.
        def update_node_check(node)
            if Puppet.features.rails? and Puppet[:storeconfigs]
                Puppet::Rails.connect

                host = Puppet::Rails::Host.find_or_create_by_name(node.name)
                host.last_freshcheck = Time.now
                host.save
            end
        end
    end
end
