require 'active_record'

module ActiveRecord
  module ConnectionAdapters
    class MakaraAbstractAdapter < ::Makara::Proxy


      class ErrorHandler < ::Makara::ErrorHandler


        HARSH_ERRORS = [
          'ActiveRecord::RecordNotUnique',
          'ActiveRecord::InvalidForeignKey',
          'Makara::Errors::BlacklistConnection'
        ].map(&:freeze).freeze


        CONNECTION_MATCHERS = [
          /(closed|lost|no|terminating|terminated)\s?([^\s]+)?\sconnection/i,
          /gone away/i,
          /connection[^:]+refused/i,
          /could not connect/i,
          /can\'t connect/i,
          /cannot connect/i,
          /connection[^:]+closed/i,
          /can\'t get socket descriptor/i,
          /connection to [a-zA-Z0-9.]+:[0-9]+ refused/i
        ].map(&:freeze).freeze


        def handle(connection)

          yield

        rescue Exception => e
          # do it via class name to avoid version-specific constant dependencies
          case e.class.name
          when *harsh_errors
            harshly(e)
          else
            if connection_message?(e) || custom_error_message?(connection, e)
              gracefully(connection, e)
            else
              harshly(e)
            end
          end

        end


        def harsh_errors
          HARSH_ERRORS
        end


        def connection_matchers
          CONNECTION_MATCHERS
        end


        def connection_message?(message)
          message = message.to_s.downcase

          case message
          when *connection_matchers
            true
          else
            false
          end
        end


        def custom_error_message?(connection, message)
          custom_error_matchers = connection._makara_custom_error_matchers
          return false if custom_error_matchers.empty?

          message = message.to_s

          custom_error_matchers.each do |matcher|

            if matcher.is_a?(String)

              # accept strings that look like "/.../" as a regex
              if matcher =~ /^\/(.+)\/([a-z])?$/

                options = $2 ? (($2.include?('x') ? Regexp::EXTENDED : 0) |
                          ($2.include?('i') ? Regexp::IGNORECASE : 0) |
                          ($2.include?('m') ? Regexp::MULTILINE : 0)) : 0

                matcher = Regexp.new($1, options)
              end
            end

            return true if matcher === message
          end

          false
        end


      end


      hijack_method :execute, :select_rows, :exec_query, :transaction
      send_to_all :connect, :reconnect!, :verify!, :clear_cache!, :reset!

      SQL_MASTER_MATCHERS           = [/\A\s*select.+for update\Z/i, /select.+lock in share mode\Z/i].map(&:freeze).freeze
      SQL_SLAVE_MATCHERS            = [/\A\s*select\s/i].map(&:freeze).freeze
      SQL_ALL_MATCHERS              = [/\A\s*set\s/i].map(&:freeze).freeze
      SQL_SKIP_STICKINESS_MATCHERS  = [/\A\s*show\s([\w]+\s)?(field|table|database|schema|view|index)(es|s)?/i, /\A\s*(set|describe|explain|pragma)\s/i].map(&:freeze).freeze


      def sql_master_matchers
        SQL_MASTER_MATCHERS
      end


      def sql_slave_matchers
        SQL_SLAVE_MATCHERS
      end


      def sql_all_matchers
        SQL_ALL_MATCHERS
      end


      def sql_skip_stickiness_matchers
        SQL_SKIP_STICKINESS_MATCHERS
      end


      def initialize(config)
        @error_handler = ::ActiveRecord::ConnectionAdapters::MakaraAbstractAdapter::ErrorHandler.new
        super(config)
      end


      protected


      def appropriate_connection(method_name, args)
        if needed_by_all?(method_name, args)

          handling_an_all_execution(method_name) do
            # slave pool must run first.
            @slave_pool.provide_each do |con|
              hijacked do
                yield con
              end
            end

            @master_pool.provide_each do |con|
              hijacked do
                yield con
              end
            end
          end

        else

          super(method_name, args) do |con|
            yield con
          end

        end
      end


      def should_stick?(method_name, args)
        sql = args.first.to_s
        return false if sql_skip_stickiness_matchers.any?{|m| sql =~ m }
        super
      end


      def needed_by_all?(method_name, args)
        sql = args.first.to_s
        return true if sql_all_matchers.any?{|m| sql =~ m }
        false
      end


      def needs_master?(method_name, args)
        sql = args.first.to_s
        return true if sql_master_matchers.any?{|m| sql =~ m }
        return false if sql_slave_matchers.any?{|m| sql =~ m }
        true
      end


      def connection_for(config)
        active_record_connection_for(config)
      end


      def active_record_connection_for(config)
        raise NotImplementedError
      end


    end
  end
end
