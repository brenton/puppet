require 'puppet/parser/ast/resource_reference'

# Any normal puppet resource declaration.  Can point to a definition or a
# builtin type.
class Puppet::Parser::AST
class Resource < AST::ResourceReference
    attr_accessor :title, :type, :exported, :virtual
    attr_reader :params

    # Does not actually return an object; instead sets an object
    # in the current scope.
    def evaluate(scope)
        # Evaluate all of the specified params.
        paramobjects = @params.collect { |param|
            param.safeevaluate(scope)
        }

        objtitles = @title.safeevaluate(scope)

        # it's easier to always use an array, even for only one name
        unless objtitles.is_a?(Array)
            objtitles = [objtitles]
        end

        objtype = qualified_type(scope)

        # This is where our implicit iteration takes place; if someone
        # passed an array as the name, then we act just like the called us
        # many times.
        objtitles.collect { |objtitle|
            exceptwrap :type => Puppet::ParseError do
                exp = self.exported || scope.resource.exported?
                # We want virtual to be true if exported is true.  We can't
                # just set :virtual => self.virtual in the initialization,
                # because sometimes the :virtual attribute is set *after*
                # :exported, in which case it clobbers :exported if :exported
                # is true.  Argh, this was a very tough one to track down.
                virt = self.virtual || scope.resource.virtual? || exp
                obj = Puppet::Parser::Resource.new(
                    :type => objtype,
                    :title => objtitle,
                    :params => paramobjects,
                    :file => self.file,
                    :line => self.line,
                    :exported => exp,
                    :virtual => virt,
                    :source => scope.source,
                    :scope => scope
                )

                # And then store the resource in the compiler.
                # At some point, we need to switch all of this to return
                # objects instead of storing them like this.
                scope.compiler.add_resource(scope, obj)
                obj
            end
        }.reject { |obj| obj.nil? }
    end

    # Set the parameters for our object.
    def params=(params)
        if params.is_a?(AST::ASTArray)
            @params = params
        else
            @params = AST::ASTArray.new(
                :line => params.line,
                :file => params.file,
                :children => [params]
            )
        end
    end
end
end
