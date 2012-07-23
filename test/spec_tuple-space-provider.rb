require_relative 'test-util'
require 'pione/tuple-space-server'
require 'pione/tuple-space-provider'

describe 'TupleSpaceProvider' do
  before do
    @kill = []
  end

  after do
    TupleSpaceProvider.terminate
    # kill processes
    @kill.each do |pid|
      begin
        Process.kill('KILL', pid)
      rescue Errno::ESRCH
      end
    end
  end

  it 'should get provider' do
    p1 = TupleSpaceProvider.instance
    p2 = TupleSpaceProvider.instance
    p3 = TupleSpaceProvider.instance
    p1.uuid.should == p2.uuid
    p3.uuid.should == p3.uuid
  end

  it 'should terminate' do
    TupleSpaceProvider.instance
    TupleSpaceProvider.terminate
    remote = DRbObject.new_with_uri(TupleSpaceProvider::PROVIDER_URI)
    should.raise { puts remote.uuid }
    TupleSpaceProvider.instance
    TupleSpaceProvider.terminate
  end

  it 'should move provider' do
    TupleSpaceProvider.terminate

    # provider in pid1
    pid1 = Process.fork do
      TupleSpaceServer.new
      TupleSpaceProvider.instance
      sleep 60
    end

    pid2 = Process.fork do
      TupleSpaceServer.new
      100.times do
        TupleSpaceProvider.instance
        sleep 0.1
      end
    end

    pid3 = Process.fork do
      TupleSpaceServer.new
      100.times do
        TupleSpaceProvider.instance
        sleep 0.1
      end
    end

    @kill << pid1 << pid2 << pid3

    sleep 0.1

    [pid1, pid2, pid3].should.include TupleSpaceProvider.instance.pid
    Process.kill('KILL', pid1)
    Process.waitpid(pid1)
    sleep 0.1

    [pid2, pid3].should.include TupleSpaceProvider.instance.pid
    Process.kill('KILL', pid2)
    Process.waitpid(pid2)
    sleep 0.1

    TupleSpaceProvider.instance.pid.should == pid3
  end

  it "should add tuple space server" do
    ts_server = TupleSpaceServer.new
    provider = TupleSpaceProvider.instance
    provider.add(ts_server)
    provider.tuple_space_servers.map{|ts| ts.uuid}.first.should == ts_server.uuid
  end
end
