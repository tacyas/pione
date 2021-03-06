require_relative 'test-util.rb'

include Pione

describe 'Log' do
  it 'should create without block' do
    should.not.raise { Log.new }
  end

  it 'should create with block' do
    should.not.raise { Log.new{} }
  end

  it 'should add a record' do
    log = Log.new do |l|
      l.add_record("spec_log", "action", "test")
    end
    log.records.size.should == 1
  end

  it 'should add records' do
    log = Log.new do |l|
      l.add_record("spec_log", "test1", "a")
      l.add_record("spec_log", "test2", "b")
    end
    log.records.size.should == 2
  end

  it 'should format as string' do
    log = Log.new do |l|
      l.add_record("spec_log", "action", "test")
    end
    md = /(.+)\s+[A-Z0-9]{4}\s+\.spec_log\.action:\s+\"test\"/.match(log.format)
    md.should.not.be.nil
    should.not.raise { Time.iso8601(md[1]) }
  end

  it 'should format as string' do
    log = Log.new do |l|
      l.add_record("spec_log", "test1", "a")
      l.add_record("spec_log", "test2", "b")
    end
    lines = log.format.split("\n")
    lines.size.should == 2
    md1 = /^(.+)\s+[A-Z0-9]{4}\s+\.spec_log\.test1:\s+\"a\"$/.match(lines[0])
    md1.should.not.be.nil
    should.not.raise { Time.iso8601(md1[1]) }
    md2 = /^(.+)\s+[A-Z0-9]{4}\s+\.spec_log\.test2:\s+\"b\"$/.match(lines[1])
    md2.should.not.be.nil
    should.not.raise { Time.iso8601(md2[1]) }
  end
end
