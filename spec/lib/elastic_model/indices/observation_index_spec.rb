require "spec_helper"

describe "Observation Index" do
  before( :all ) do
    @starting_time_zone = Time.zone
    Time.zone = ActiveSupport::TimeZone["Samoa"]
  end
  after( :all ) { Time.zone = @starting_time_zone }

  it "as_indexed_json should return a hash" do
    o = Observation.make!
    json = o.as_indexed_json
    expect( json ).to be_a Hash
  end

  it "sets location based on private coordinates if exist" do
    o = Observation.make!(latitude: 3.0, longitude: 4.0)
    o.update_attributes(private_latitude: 1.0, private_longitude: 2.0)
    json = o.as_indexed_json
    expect( json[:location] ).to eq "1.0,2.0"
  end

  it "sets location based on public coordinates if there are no private" do
    o = Observation.make!(latitude: 3.0, longitude: 4.0)
    json = o.as_indexed_json
    expect( json[:location] ).to eq "3.0,4.0"
  end

  it "indexes created_at based on UTC" do
    o = Observation.make!(created_at: "2014-12-31 20:00:00 -0800")
    json = o.as_indexed_json
    expect( json[:created_at].year ).to eq 2015
  end

  it "indexes created_at_details based on UTC" do
    o = Observation.make!(created_at: "2014-12-31 20:00:00 -0800")
    json = o.as_indexed_json
    expect( json[:created_at_details][:day] ).to eq 1
    expect( json[:created_at_details][:month] ).to eq 1
    expect( json[:created_at_details][:year] ).to eq 2015
  end
end
