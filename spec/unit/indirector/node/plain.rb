#!/usr/bin/env ruby

require File.dirname(__FILE__) + '/../../../spec_helper'

require 'puppet/indirector/node/plain'

describe Puppet::Node::Plain do
    before do
        @searcher = Puppet::Node::Plain.new
    end

    it "should call node_merge() on the returned node" do
        node = mock 'node'
        Puppet::Node.expects(:new).with("mynode").returns(node)
        node.expects(:fact_merge)
        @searcher.find("mynode")
    end
end
