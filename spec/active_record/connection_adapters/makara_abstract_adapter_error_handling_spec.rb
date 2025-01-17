require 'spec_helper'
require 'active_record/connection_adapters/makara_abstract_adapter'

describe ActiveRecord::ConnectionAdapters::MakaraAbstractAdapter::ErrorHandler do

  let(:handler){ described_class.new }
  let(:proxy) { FakeAdapter.new(config(1,1)) }
  let(:connection){ proxy.master_pool.connections.first }

  [
    %|Mysql::Error: : INSERT INTO `watchers` (`user_id`, `watchable_id`, `watchable_type`) VALUES|,
    %|PGError: ERROR: column items.user_id does not exist LINE 1: SELECT "items".* FROM "items" WHERE ("items".user_id = 4) OR|
  ].each do |msg|
    it "should properly evaluate errors like: #{msg}" do
      expect(handler).not_to be_connection_message(msg)
    end

    it 'should raise the error' do
      expect{
        handler.handle(connection) do
          raise msg
        end
      }.to raise_error(msg)
    end
  end

  [
    %|Mysql2::Error: closed MySQL connection: SELECT `users`.* FROM `users`|,
    %|Mysql2::Error: MySQL server has gone away: SELECT `users`.* FROM `users`|,
    %|Mysql2::Error (Can't connect to MySQL server on '123.456.789.234' (111))|,
    %|Mysql2::Error (Cannot connect to MySQL server on '123.456.789.234' (111))|,
    %|Mysql2::Error: Lost connection to MySQL server during query: SELECT `geographies`.* FROM `geographies`|,
    %|PGError: server closed the connection unexpectedly This probably me|,
    %|Could not connect to server: Connection refused Is the server running on host|,
    %|PG::AdminShutdown: FATAL:  terminating connection due to administrator command FATAL:  terminating connection due to administrator command|,
    %|PG::ConnectionBad: PQconsumeInput() SSL connection has been closed unexpectedly: SELECT  1 AS one FROM "users"  WHERE "users"."registration_ip" = '10.0.2.2' LIMIT 1|,
    %|PG::UnableToSend: no connection to the server|,
    %|PG::ConnectionBad (could not connect to server: Connection refused|,
    %|PG::ConnectionBad: PQsocket() can't get socket descriptor:|,
    %|org.postgresql.util.PSQLException: Connection to localhost:123 refused. Check that the hostname and port are correct and that the postmaster is accepting TCP/IP connections.|
  ].each do |msg|
    it "should properly evaluate connection messages like: #{msg}" do
      expect(handler).to be_connection_message(msg)
    end

    it 'should blacklist the connection' do
      expect {
        handler.handle(connection) do
          raise msg
        end
      }.to raise_error(Makara::Errors::BlacklistConnection)
    end
  end

  describe 'custom errors' do

    let(:config_path) { File.join(File.expand_path('../../../', __FILE__), 'support', 'mysql2_database_with_custom_errors.yml') }
    let(:config) { YAML.load_file(config_path)['test'] }
    let(:handler){ described_class.new }
    let(:proxy) { FakeAdapter.new(config) }
    let(:connection){ proxy.master_pool.connections.first }
    let(:msg1) { "ActiveRecord::StatementInvalid: Mysql2::Error: Unknown command1: SELECT `users`.* FROM `users` WHERE `users`.`id` = 53469 LIMIT 1" }
    let(:msg2) { "activeRecord::statementInvalid: mysql2::error: unknown command2: SELECT `users`.* FROM `users` WHERE `users`.`id` = 53469 LIMIT 1" }
    let(:msg3) { "ActiveRecord::StatementInvalid: Mysql2::Error: Unknown command3: SELECT `users`.* FROM `users` WHERE `users`.`id` = 53469 LIMIT 1" }
    let(:msg4) { "ActiveRecord::StatementInvalid: Mysql2::Error: Unknown command3:" }

    it "identifies custom errors" do
      expect(handler).to be_custom_error_message(connection, msg1)
      expect(handler).to be_custom_error_message(connection, msg2)
      expect(handler).to_not be_custom_error_message(connection, msg3)
      expect(handler).to be_custom_error_message(connection, msg4)
    end

    it "blacklists the connection" do
      expect {
        handler.handle(connection) do
          raise msg1
        end
      }.to raise_error(Makara::Errors::BlacklistConnection)
    end

  end


end
