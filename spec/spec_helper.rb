$LOAD_PATH << "." unless $LOAD_PATH.include? "." # moronic 1.9.2 breaks things bad

require 'bundler'
Bundler.setup
Bundler.require :default, :test

require 'yaml'
require 'amqp-spec/rspec'
require 'shared_examples'

require 'mq'

def rspec2?
  defined?(RSpec)
end

# Done is defined as noop to help share examples between evented and non-evented specs
def done
end

RSPEC       = rspec2? ? RSpec : Spec

amqp_config = File.dirname(__FILE__) + '/amqp.yml'

AMQP_OPTS   = unless File.exists? amqp_config
                {:user  => 'guest',
                 :pass  => 'guest',
                 :host  => '10.211.55.2',
                 :vhost => '/'}
              else
                class Hash
                  def symbolize_keys
                    self.inject({}) { |result, (key, value)|
                      new_key         = case key
                                          when String then
                                            key.to_sym
                                          else
                                            key
                                        end
                      new_value       = case value
                                          when Hash then
                                            value.symbolize_keys
                                          else
                                            value
                                        end
                      result[new_key] = new_value
                      result
                    }
                  end
                end

                YAML::load_file(amqp_config).symbolize_keys[:test]
              end