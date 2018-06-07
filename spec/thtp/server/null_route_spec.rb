require 'spec_helper'

RSpec.describe THTP::NullRoute do
  subject(:app) { described_class.new }

  it 'responds with a thrift bad-request ApplicationException' do
    post '/test/route'

    expect(last_response).to_not be_ok
    expect(last_response).to be_thrift_error_response(THTP::BadRequestError)
  end

  it 'defaults to JsonProtocol' do
    put '/more-tests', who: :are_you

    expect(last_response).to_not be_ok
    expect(last_response.content_type).to eq THTP::Encoding::JSON
  end

  it 'matches its response to the Thrift protocol of the request' do
    header 'CONTENT_TYPE', THTP::Encoding::BINARY
    get '/wow/such/test', param: :val

    expect(last_response).to_not be_ok
    expect(last_response.content_type).to eq THTP::Encoding::BINARY
  end
end
