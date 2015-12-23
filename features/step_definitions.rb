require 'securerandom'
require 'aws-sdk-core'
require 'aws-record'

def cleanup_table
  begin
    @client.delete_table(table_name: @table_name)
    puts "Cleaned up table: #{@table_name}"
    @table_name = nil
  rescue Aws::DynamoDB::Errors::ResourceNotFoundException
    puts "Cleanup: Table #{@table_name} doesn't exist, continuing."
    @table_name = nil
  rescue Aws::DynamoDB::Errors::ResourceInUseException => e
    @client.wait_until(:table_exists, table_name: @table_name)
    retry
  end
end

Before do
  @client = Aws::DynamoDB::Client.new(region: "us-east-1")
end

After("@item") do
  cleanup_table
end

After("@table") do
  cleanup_table
end

Given(/^a DynamoDB table named '([^"]*)' with data:$/) do |table, string|
  data = JSON.parse(string)
  @table_name = "#{table}_#{SecureRandom.uuid}"
  attr_def = data.inject([]) do |acc, row|
    acc << {
      attribute_name: row['attribute_name'],
      attribute_type: row['attribute_type']
    }
  end
  key_schema = data.inject([]) do |acc, row|
    acc << {
      attribute_name: row['attribute_name'],
      key_type: row['key_type']
    }
  end
  @client.create_table(
    table_name: @table_name,
    attribute_definitions: attr_def,
    key_schema: key_schema,
    provisioned_throughput: {
      read_capacity_units: 1,
      write_capacity_units: 1
    }
  )
  @client.wait_until(:table_exists, table_name: @table_name) do |w|
    w.delay = 5
    w.max_attempts = 25
  end
end

Given(/^an aws\-record model with data:$/) do |string|
  data = JSON.parse(string)
  @model = Class.new do
    include(Aws::Record)
  end
  @table_name ||= "test_table_#{SecureRandom.uuid}"
  @model.set_table_name(@table_name)
  data.each do |row|
    opts = {}
    opts[:database_attribute_name] = row['database_name']
    opts[:hash_key] = row['hash_key']
    opts[:range_key] = row['range_key']
    @model.send(:"#{row['method']}", row['name'].to_sym, opts)
  end
end

When(/^we create a new instance of the model with attribute value pairs:$/) do |string|
  data = JSON.parse(string)
  @instance = @model.new
  data.each do |row|
    attribute, value = row
    @instance.send(:"#{attribute}=", value)
  end
end

When(/^we save the model instance$/) do
  @instance.save
end

Then(/^the DynamoDB table should have an object with key values:$/) do |string|
  data = JSON.parse(string)
  key = {}
  data.each do |row|
    attribute, value = row
    key[attribute] = value
  end
  resp = @client.get_item(
    table_name: @table_name,
    key: key
  )
  expect(resp.item).not_to eq(nil)
end

Given(/^an item exists in the DynamoDB table with item data:$/) do |string|
  data = JSON.parse(string)
  @client.put_item(
    table_name: @table_name,
    item: data
  )
end

When(/^we call the 'find' class method with parameter data:$/) do |string|
  data = JSON.parse(string, symbolize_names: true)
  @instance = @model.find(data)
end

Then(/^we should receive an aws\-record item with attribute data:$/) do |string|
  data = JSON.parse(string, symbolize_names: true)
  data.each do |key, value|
    expect(@instance.send(key)).to eq(value)
  end
end

When(/^we call 'delete!' on the aws\-record item instance$/) do
  @instance.delete!
end

Then(/^the DynamoDB table should not have an object with key values:$/) do |string|
  data = JSON.parse(string)
  key = {}
  data.each do |row|
    attribute, value = row
    key[attribute] = value
  end
  resp = @client.get_item(
    table_name: @table_name,
    key: key
  )
  expect(resp.item).to eq(nil)
end

When(/^we create a table migration for the model$/) do
  @migration = Aws::Record::TableMigration.new(@model)
end

When(/^we call 'create!' with parameters:$/) do |string|
  data = JSON.parse(string, symbolize_names: true)
  @migration.create!(data)
end

Then(/^eventually the table should exist in DynamoDB$/) do
  @client.wait_until(:table_exists, table_name: @table_name) do |w|
    w.delay = 5
    w.max_attempts = 25
  end
  true
end

Then(/^calling 'table_exists\?' on the model should return "([^"]*)"$/) do |b|
  boolean = b == "false" || b.nil? ? false : true
  expect(@model.table_exists?).to eq(boolean)
end

When(/^we call 'delete!' on the migration$/) do
  @migration.delete!
end

Then(/^eventually the table should not exist in DynamoDB$/) do
  @client.wait_until(:table_not_exists, table_name: @table_name) do |w|
    w.delay = 5
    w.max_attempts = 25
  end
end

When(/^we call 'wait_until_available' on the migration$/) do
  @migration.wait_until_available
end

When(/^we call 'update!' on the migration with parameters:$/) do |string|
  data = JSON.parse(string, symbolize_names: true)
  @migration.update!(data)
  # Wait until table is active again before proceeding.
  @client.wait_until(:table_exists, table_name: @table_name) do |w|
    w.delay = 5
    w.max_attempts = 25
  end
end

Then(/^calling "([^"]*)" on the model should return:$/) do |method, retval|
  expected = JSON.parse(retval, symbolize_names: true)
  expect(@model.send(method)).to eq(expected)
end
