require File.dirname(__FILE__) + '/../spec_helper'

shared_examples_for "an ObservationsController" do

  describe "create" do
    it "should create" do
      expect {
        post :create, :format => :json, :observation => {:species_guess => "foo"}
      }.to change(Observation, :count).by(1)
      o = Observation.last
      expect(o.user_id).to eq(user.id)
      expect(o.species_guess).to eq ("foo")
    end

    it "should include private coordinates in create response" do
      post :create, :format => :json, :observation => {:latitude => 1.2345, :longitude => 1.2345, :geoprivacy => Observation::PRIVATE}
      o = Observation.last
      expect(o).to be_coordinates_obscured
      expect(response.body).to be =~ /#{o.private_latitude}/
      expect(response.body).to be =~ /#{o.private_longitude}/
    end

    it "should not fail if species_guess is a question mark" do
      post :create, :format => :json, :observation => {:species_guess => "?"}
      expect(response).to be_success
      o = Observation.last
      expect(o.species_guess).to eq('?')
    end

    it "should accept nested observation_field_values" do
      of = ObservationField.make!
      post :create, :format => :json, :observation => {
        :species_guess => "zomg", 
        :observation_field_values_attributes => [
          {
            :observation_field_id => of.id,
            :value => "foo"
          }
        ]
      }
      expect(response).to be_success
      o = Observation.last
      expect(o.observation_field_values.last.observation_field).to eq(of)
      expect(o.observation_field_values.last.value).to eq("foo")
    end

    it "should allow Google Street View photos" do
      post :create, :format => :json, :observation => {:species_guess => "tree"}, :google_street_view_photos => {
        "0" => "http://maps.googleapis.com/maps/api/streetview?size=600x300&location=37.903042,-122.24697600000002&heading=-73.33342317239405&pitch=28.839156732145224&fov=180&sensor=false"
      }
      expect(response).to be_success
      o = Observation.last
      expect(o.photos.last).to be_a GoogleStreetViewPhoto
    end

    it "should not fail with a dot for a species_guess" do
      expect {
        post :create, :format => :json, :observation => {:species_guess => "."}
      }.not_to raise_error
    end

    it "should handle invalid time zones" do
      expect {
        post :create, :format => :json, :observation => {:species_guess => "foo", :observed_on_string => "2014-07-01 14:23", :time_zone => "Eastern Time (US &amp; Canada)"}
      }.not_to raise_error
    end

    describe "project_id" do
      let(:p) { Project.make! }

      it "should add to project" do
        post :create, :format => :json, :observation => {:species_guess => "foo"}, :project_id => p.id
        expect(p.observations.count).to eq 1
      end

      it "should not create a project user if one doesn't exist" do
        expect(p.project_users.where(:user_id => user.id)).to be_blank
        post :create, :format => :json, :observation => {:species_guess => "foo"}, :project_id => p.id
        p.reload
        expect(p.project_users.where(:user_id => user.id)).to be_blank
      end

      it "should add to project with has_media rule if photo present" do
        photo = LocalPhoto.make!(:user => user)
        project = Project.make!
        project_rule = ProjectObservationRule.make!(:ruler => project, :operator => "has_media?")
        post :create, :format => :json, :project_id => project.id, :observation => {:species_guess => "foo"}, :local_photos => {
          "0" => photo.id
        }
        o = user.observations.last
        expect(o.projects).to include(project)
      end

      it "should set the project_observation's user_id" do
        post :create, :format => :json, :observation => {:species_guess => "foo"}, :project_id => p.id
        po = user.observations.last.project_observations.where(project_id: p.id).first
        expect( po.user_id ).to eq user.id
      end
    end

    it "should not duplicate observations with the same uuid" do
      uuid = "some really long identifier"
      o = Observation.make!(:user => user, :uuid => uuid)
      post :create, :format => :json, :observation => {:uuid => uuid}
      expect(Observation.where(:uuid => uuid).count).to eq 1
    end

    it "should update attributes for an existing observation with the same uuid" do
      uuid = "some really long identifier"
      o = Observation.make!(:user => user, :uuid => uuid)
      post :create, :format => :json, :observation => {:uuid => uuid, :description => "this is a WOAH"}
      expect(Observation.where(:uuid => uuid).count).to eq 1
      o.reload
      expect(o.description).to eq "this is a WOAH"
    end

    it "should duplicate observations with the same uuid if made by different users" do
      # in theory this is statistically impossible if people use rfc4122 UUIDs, but people and statistics are evil
      uuid = "some really long identifier"
      o = Observation.make!(:uuid => uuid)
      post :create, :format => :json, :observation => {:uuid => uuid}
      expect(Observation.where(:uuid => uuid).count).to eq 2
    end
  end

  describe "destroy" do
    it "should destroy" do
      o = Observation.make!(:user => user)
      delete :destroy, :format => :json, :id => o.id
      expect(Observation.find_by_id(o.id)).to be_blank
    end

    it "should not destory other people's observations" do
      o = Observation.make!
      delete :destroy, :format => :json, :id => o.id
      expect(Observation.find_by_id(o.id)).not_to be_blank
    end
  end

  describe "show" do
    it "should provide private coordinates for user's observation" do
      o = Observation.make!(:user => user, :latitude => 1.23456, :longitude => 7.890123, :geoprivacy => Observation::PRIVATE)
      get :show, :format => :json, :id => o.id
      expect(response.body).to be =~ /#{o.private_latitude}/
      expect(response.body).to be =~ /#{o.private_longitude}/
    end

    it "should not provide private coordinates for another user's observation" do
      o = Observation.make!(:latitude => 1.23456, :longitude => 7.890123, :geoprivacy => Observation::PRIVATE)
      get :show, :format => :json, :id => o.id
      expect(response.body).not_to be =~ /#{o.private_latitude}/
      expect(response.body).not_to be =~ /#{o.private_longitude}/
    end

    it "should not include photo metadata" do
      p = LocalPhoto.make!(:metadata => {:foo => "bar"})
      expect(p.metadata).not_to be_blank
      o = Observation.make!(:user => p.user, :taxon => Taxon.make!)
      op = ObservationPhoto.make!(:photo => p, :observation => o)
      get :show, :format => :json, :id => o.id
      response_obs = JSON.parse(response.body)
      response_photo = response_obs['observation_photos'][0]['photo']
      expect(response_photo).not_to be_blank
      expect(response_photo['metadata']).to be_blank
    end

    it "should include observation field values" do
      ofv = ObservationFieldValue.make!
      get :show, :format => :json, :id => ofv.observation_id
      response_obs = JSON.parse(response.body)
      expect(response_obs['observation_field_values'].first['value']).to eq(ofv.value)
    end

    it "should include observation field values with observation field names" do
      ofv = ObservationFieldValue.make!
      get :show, :format => :json, :id => ofv.observation_id
      response_obs = JSON.parse(response.body)
      expect(response_obs['observation_field_values'].first['observation_field']['name']).to eq(ofv.observation_field.name)
    end

    it "should include comments" do
      o = Observation.make!
      c = Comment.make!(:parent => o)
      get :show, :format => :json, :id => o.id
      response_obs = JSON.parse(response.body)
      expect(response_obs['comments'].first['body']).to eq(c.body)
    end

    it "should include comment user icons" do
      o = Observation.make!
      c = Comment.make!(:parent => o)
      c.user.update_attributes(:icon => open(File.dirname(__FILE__) + '/../fixtures/files/egg.jpg'))
      get :show, :format => :json, :id => o.id
      response_obs = JSON.parse(response.body)
      expect(response_obs['comments'].first['user']['user_icon_url']).not_to be_blank
    end

    it "should include identifications" do
      o = Observation.make!
      i = Identification.make!(:observation => o)
      get :show, :format => :json, :id => o.id
      response_obs = JSON.parse(response.body)
      expect(response_obs['identifications'].first['taxon_id']).to eq(i.taxon_id)
    end

    it "should include identification user icons" do
      o = Observation.make!
      i = Identification.make!(:observation => o)
      i.user.update_attributes(:icon => open(File.dirname(__FILE__) + '/../fixtures/files/egg.jpg'))
      get :show, :format => :json, :id => o.id
      response_obs = JSON.parse(response.body)
      expect(response_obs['identifications'].first['user']['user_icon_url']).not_to be_blank
    end

    it "should include identification taxon icons" do
      load_test_taxa
      o = Observation.make!
      t = Taxon.make!(:iconic_taxon => @Amphibia)
      i = Identification.make!(:observation => o)
      get :show, :format => :json, :id => o.id
      response_obs = JSON.parse(response.body)
      expect(response_obs['identifications'].first['taxon']['image_url']).not_to be_blank
    end

    it "should include identification taxon common name" do
      tn = TaxonName.make!(:lexicon => "English")
      o = Observation.make!(:taxon => tn.taxon)
      get :show, :format => :json, :id => o.id
      response_obs = JSON.parse(response.body)
      expect(response_obs['identifications'].first['taxon']['common_name']['name']).not_to be_blank
    end

    it "should include taxon rank level"
  end

  describe "update" do
    before do
      @o = Observation.make!(:user => user)
    end

    it "should update" do
      put :update, :format => :json, :id => @o.id, :observation => {:species_guess => "i am so updated"}
      @o.reload
      expect(@o.species_guess).to eq("i am so updated")
    end

    it "should accept nested observation_field_values" do
      of = ObservationField.make!
      put :update, :format => :json, :id => @o.id, :observation => {
        :observation_field_values_attributes => {
          "0" => {
            :observation_field_id => of.id,
            :value => "foo"
          }
        }
      }
      expect(response).to be_success
      @o.reload
      expect(@o.observation_field_values.last.observation_field).to eq(of)
      expect(@o.observation_field_values.last.value).to eq("foo")
    end

    it "should updating existing observation_field_values" do
      ofv = ObservationFieldValue.make!(:value => "foo", :observation => @o)
      put :update, :format => :json, :id => ofv.observation_id, :observation => {
        :observation_field_values_attributes => {
          "0" => {
            :id => ofv.id,
            :observation_field_id => ofv.observation_field_id,
            :value => "bar"
          }
        }
      }
      expect(response).to be_success
      ofv.reload
      expect(ofv.value).to eq "bar"
    end

    it "should updating existing observation_field_values by observation_field_id" do
      o = Observation.make!(:user => user)
      ofv = ObservationFieldValue.make!(:value => "foo", :observation => o)
      put :update, :format => :json, :id => ofv.observation_id, :observation => {
        :observation_field_values_attributes => {
          "0" => {
            :observation_field_id => ofv.observation_field_id,
            :value => "bar"
          }
        }
      }
      expect(response).to be_success
      ofv.reload
      expect(ofv.value).to eq "bar"
    end

    it "should updating existing observation_field_values by observation_field_id even if they're project fields" do
      pof = ProjectObservationField.make!
      po = make_project_observation(:project => pof.project, :user => user)
      ofv = ObservationFieldValue.make!(:value => "foo", :observation => po.observation, :observation_field => pof.observation_field)
      put :update, :format => :json, :id => ofv.observation_id, :observation => {
        :observation_field_values_attributes => {
          "0" => {
            :observation_field_id => ofv.observation_field_id,
            :value => "bar"
          }
        }
      }
      expect(response).to be_success
      ofv.reload
      expect(ofv.value).to eq "bar"
    end

    it "should allow removal of nested observation_field_values" do
      ofv = ObservationFieldValue.make!(:value => "foo", :observation => @o)
      expect(@o.observation_field_values).not_to be_blank
      put :update, :format => :json, :id => ofv.observation_id, :observation => {
        :observation_field_values_attributes => {
          "0" => {
            :_destroy => true,
            :id => ofv.id,
            :observation_field_id => ofv.observation_field_id,
            :value => ofv.value
          }
        }
      }
      expect(response).to be_success
      @o.reload
      expect(@o.observation_field_values).to be_blank
    end

    it "should respond with 410 for deleted observations" do
      o = Observation.make!(:user => user)
      oid = o.id
      o.destroy
      put :update, :format => :json, :id => oid, :observation => {:description => "this is different"}
      expect(response.status).to eq 410
    end

    it "should assume request lat/lon are the true coordinates" do
      o = make_observation_of_threatened(:user => user)
      lat, lon, plat, plon = [
        o.latitude,
        o.longitude,
        o.private_latitude,
        o.private_longitude
      ]
      expect(lat).not_to eq plat
      put :update, :format => :json, :id => o.id, :observations => [{:latitude => plat, :longitude => plon}]
      o.reload
      expect(o.private_latitude).to eq plat
    end

    it "should not change the true coordinates when switching to a threatened taxon and back" do
      normal = Taxon.make!
      threatened = Taxon.make!(:threatened)
      o = Observation.make!(:user => user, :taxon => normal, :latitude => 1, :longitude => 1)
      expect(o.latitude.to_f).to eq 1.0
      put :update, :format => :json, :id => o.id, :observation => {:taxon_id => threatened.id}
      o.reload
      expect(o.private_latitude).not_to be_blank
      expect(o.private_latitude).not_to eq o.latitude
      expect(o.private_latitude.to_f).to eq 1.0
      put :update, :format => :json, :id => o.id, :observation => {:taxon_id => normal.id}
      o.reload
      expect(o.private_latitude).to be_blank
      expect(o.latitude.to_f).to eq 1.0
    end

    it "should deal with updating the taxon_id" do
      t1 = Taxon.make!
      t2 = Taxon.make!
      t3 = Taxon.make!
      o = Observation.make!(taxon: t1, user: user)
      o.update_attributes(taxon: t2)
      o.reload
      expect( o.identifications.count ).to eq 2
      put :update, format: :json, id: o.id, observation: {taxon_id: t3.id}
      o.reload
      expect( o.identifications.count ).to eq 3
    end
  end

  describe "by_login" do
    before(:each) { enable_elastic_indexing([ Observation ]) }
    after(:each) { disable_elastic_indexing([ Observation ]) }

    it "should get user's observations" do
      3.times { Observation.make!(:user => user) }
      get :by_login, :format => :json, :login => user.login
      json = JSON.parse(response.body)
      expect(json.size).to eq(3)
    end

    it "should allow filtering by updated_since" do
      oldo = Observation.make!(:created_at => 1.day.ago, :updated_at => 1.day.ago, :user => user)
      expect(oldo.updated_at).to be < 1.minute.ago
      newo = Observation.make!(:user => user)
      get :by_login, :format => :json, :login => user.login, :updated_since => (newo.updated_at - 1.minute).iso8601
      json = JSON.parse(response.body)
      expect(json.detect{|o| o['id'] == newo.id}).not_to be_blank
      expect(json.detect{|o| o['id'] == oldo.id}).to be_blank
    end

    it "should return no results if updated_since is specified but incorrectly formatted" do
      oldo = Observation.make!(:created_at => 1.day.ago, :updated_at => 1.day.ago, :user => user)
      expect(oldo.updated_at).to be < 1.minute.ago
      newo = Observation.make!(:user => user)
      stamp = (newo.updated_at - 1.minute).iso8601
      bad_stamp = stamp.gsub(/\:/, '-')
      get :by_login, :format => :json, :login => user.login, :updated_since => bad_stamp
      json = JSON.parse(response.body)
      expect(json).to be_blank
    end

    it "should include deleted observation IDs when filtering by updated_since" do
      oldo = Observation.make!(:created_at => 1.day.ago, :updated_at => 1.day.ago)
      expect(oldo.updated_at).to be < 1.minute.ago
      delo1 = Observation.make!(:user => user)
      delo1.destroy
      delo2 = Observation.make!(:user => user)
      delo2.destroy
      get :by_login, :format => :json, :login => user.login, :updated_since => 2.days.ago.iso8601
      expect(response.headers["X-Deleted-Observations"].split(',')).to include(delo1.id.to_s)
      expect(response.headers["X-Deleted-Observations"].split(',')).to include(delo2.id.to_s)
    end

    it "should not include deleted observation IDs by other people" do
      oldo = Observation.make!(:created_at => 1.day.ago, :updated_at => 1.day.ago)
      expect(oldo.updated_at).to be < 1.minute.ago
      delo1 = Observation.make!(:user => user)
      delo1.destroy
      delo2 = Observation.make!
      delo2.destroy
      get :by_login, :format => :json, :login => user.login, :updated_since => 2.days.ago.iso8601
      expect(response.headers["X-Deleted-Observations"].split(',')).to include(delo1.id.to_s)
      expect(response.headers["X-Deleted-Observations"].split(',')).not_to include(delo2.id.to_s)
    end

    it "should return private observations for bounding box queries when viewer is owner" do
      o = Observation.make!(:latitude => 1, :longitude => 1, :geoprivacy => Observation::PRIVATE, :user => user)
      expect(o.private_geom).not_to be_blank
      get :by_login, :format => :json, :login => user.login, :swlat => 0, :swlng => 0, :nelat => 2, :nelng => 2
      json = JSON.parse(response.body)
      expect(json.map{|jo| jo['id']}).to include o.id
    end

    it "should include private coordinates when viewer is owner" do
      o = Observation.make!(:latitude => 1.2345, :longitude => 1.2345, :geoprivacy => Observation::PRIVATE, :user => user)
      expect(o.private_geom).not_to be_blank
      get :by_login, :format => :json, :login => user.login, :swlat => 0, :swlng => 0, :nelat => 2, :nelng => 2
      json = JSON.parse(response.body)
      json_obs = json.detect{|jo| jo['id'] == o.id}
      expect(json_obs).not_to be_blank
      expect(json_obs['private_latitude']).to eq o.private_latitude.to_s
    end
  end

  describe "index" do
    before(:each) { enable_elastic_indexing( Observation, Place ) }
    after(:each) { disable_elastic_indexing( Observation, Place ) }

    it "should allow search" do
      expect {
        get :index, :format => :json, :q => "foo"
      }.not_to raise_error
    end

    it "should allow sorting with different cases" do
      o = Observation.make!
      get :index, format: :json, sort: "ASC"
      expect( JSON.parse(response.body).length ).to eq 1
      get :index, format: :json, sort: "asc"
      expect( JSON.parse(response.body).length ).to eq 1
      get :index, format: :json, sort: "DeSC"
      expect( JSON.parse(response.body).length ).to eq 1
    end

    it "should filter by hour range" do
      o = Observation.make!(:observed_on_string => "2012-01-01 13:13")
      expect(o.time_observed_at).not_to be_blank
      get :index, :format => :json, :h1 => 13, :h2 => 14
      json = JSON.parse(response.body)
      expect(json.detect{|obs| obs['id'] == o.id}).not_to be_blank
    end

    it "should filter by date range" do
      o = Observation.make!(:observed_on_string => "2012-01-01 13:13")
      expect(o.time_observed_at).not_to be_blank
      get :index, :format => :json, :d1 => "2011-12-31", :d2 => "2012-01-04"
      json = JSON.parse(response.body)
      expect(json.detect{|obs| obs['id'] == o.id}).not_to be_blank
    end

    it "should filter by time range" do
      o1 = Observation.make!(:observed_on_string => "2014-03-28T18:57:41+00:00")
      o2 = Observation.make!(:observed_on_string => "2014-03-28T08:57:41+00:00")
      get :index, :format => :json, :d1 => "2014-03-28T12:57:41+00:00", :d2 => "2014-03-28T22:57:41+00:00"
      json = JSON.parse(response.body)
      expect(json.detect{|obs| obs['id'] == o1.id}).not_to be_blank
      expect(json.detect{|obs| obs['id'] == o2.id}).to be_blank
    end

    it "should filter by month range" do
      o1 = Observation.make!(:observed_on_string => "2012-01-01 13:13")
      o2 = Observation.make!(:observed_on_string => "2010-03-01 13:13")
      get :index, :format => :json, :m1 => 11, :m2 => 3
      json = JSON.parse(response.body)
      expect(json.detect{|obs| obs['id'] == o1.id}).not_to be_blank
      expect(json.detect{|obs| obs['id'] == o2.id}).not_to be_blank
    end

    it "should filter by week of the year" do
      o1 = Observation.make!(:observed_on_string => "2012-01-05 13:13")
      o2 = Observation.make!(:observed_on_string => "2010-03-01 13:13")
      get :index, :format => :json, :week => 1
      json = JSON.parse(response.body)
      expect(json.detect{|obs| obs['id'] == o1.id}).not_to be_blank
      expect(json.detect{|obs| obs['id'] == o2.id}).to be_blank
    end

    it "should filter by captive=true" do
      captive = Observation.make!(:captive_flag => "1")
      wild = Observation.make!(:captive_flag => "0")
      get :index, :format => :json, :captive => true
      json = JSON.parse(response.body)
      expect(json.detect{|obs| obs['id'] == wild.id}).to be_blank
      expect(json.detect{|obs| obs['id'] == captive.id}).not_to be_blank
    end

    it "should filter by captive=false" do
      captive = Observation.make!(captive_flag: "1")
      wild = Observation.make!(captive_flag: "0")
      get :index, format: :json, captive: false
      json = JSON.parse(response.body)
      expect(json.detect{|obs| obs['id'] == captive.id}).to be_blank
      expect(json.detect{|obs| obs['id'] == wild.id}).not_to be_blank
    end

    it "should filter by captive when quality metrics used" do
      captive = Observation.make!
      captive_qm = QualityMetric.make!(:observation => captive, :metric => QualityMetric::WILD, :agree => false)
      wild = Observation.make!
      wild_qm = QualityMetric.make!(:observation => wild, :metric => QualityMetric::WILD, :agree => true)
      get :index, :format => :json, :captive => true
      json = JSON.parse(response.body)
      expect(json.detect{|obs| obs['id'] == wild.id}).to be_blank
      expect(json.detect{|obs| obs['id'] == captive.id}).not_to be_blank
    end

    it "captive filter=false should include nil" do
      o = Observation.make!
      get :index, :format => :json, :captive => false
      json = JSON.parse(response.body)
      expect(json.detect{|obs| obs['id'] == o.id}).not_to be_blank
    end

    it "should include pagination data in headers" do
      3.times { Observation.make! }
      total_entries = Observation.count
      get :index, :format => :json, :page => 2, :per_page => 30
      expect(response.headers["X-Total-Entries"].to_i).to eq(total_entries)
      expect(response.headers["X-Page"].to_i).to eq(2)
      expect(response.headers["X-Per-Page"].to_i).to eq(30)
    end

    it "should not include photo metadata" do
      p = LocalPhoto.make!(:metadata => {:foo => "bar"})
      expect(p.metadata).not_to be_blank
      o = Observation.make!(:user => p.user, :taxon => Taxon.make!)
      op = ObservationPhoto.make!(:photo => p, :observation => o)
      get :index, :format => :json, :taxon_id => o.taxon_id
      json = JSON.parse(response.body)
      response_obs = json.detect{|obs| obs['id'] == o.id}
      expect(response_obs).not_to be_blank
      response_photo = response_obs['photos'].first
      expect(response_photo).not_to be_blank
      expect(response_photo['metadata']).to be_blank
    end

    it "should filter by conservation_status" do
      cs = without_delay {ConservationStatus.make!}
      t = cs.taxon
      o1 = Observation.make!(:taxon => t)
      o2 = Observation.make!(:taxon => Taxon.make!)
      get :index, :format => :json, :cs => cs.status
      json = JSON.parse(response.body)
      expect(json.detect{|obs| obs['id'] == o1.id}).not_to be_blank
      expect(json.detect{|obs| obs['id'] == o2.id}).to be_blank
    end

    it "should filter by conservation_status authority" do
      cs1 = without_delay {ConservationStatus.make!(:authority => "foo")}
      cs2 = without_delay {ConservationStatus.make!(:authority => "bar", :status => cs1.status)}
      o1 = Observation.make!(:taxon => cs1.taxon)
      o2 = Observation.make!(:taxon => cs2.taxon)
      get :index, :format => :json, :csa => cs1.authority
      json = JSON.parse(response.body)
      expect(json.detect{|obs| obs['id'] == o1.id}).not_to be_blank
      expect(json.detect{|obs| obs['id'] == o2.id}).to be_blank
    end

    it "should filter by establishment means" do
      p = make_place_with_geom
      lt1 = without_delay {ListedTaxon.make!(:establishment_means => ListedTaxon::INTRODUCED, :list => p.check_list, :place => p)}
      lt2 = without_delay {ListedTaxon.make!(:establishment_means => ListedTaxon::NATIVE, :list => p.check_list, :place => p)}
      o1 = Observation.make!(:taxon => lt1.taxon, :latitude => p.latitude, :longitude => p.longitude)
      o2 = Observation.make!(:taxon => lt2.taxon, :latitude => p.latitude, :longitude => p.longitude)
      get :index, :format => :json, :establishment_means => lt1.establishment_means, :place_id => p.id
      json = JSON.parse(response.body)
      expect(json.detect{|obs| obs['id'] == o1.id}).not_to be_blank
      expect(json.detect{|obs| obs['id'] == o2.id}).to be_blank
    end

    it "should include common names" do
      tn = TaxonName.make!(:lexicon => TaxonName::ENGLISH)
      o = Observation.make!(:taxon => tn.taxon)
      get :index, :format => :json, :taxon_id => tn.taxon_id
      json = JSON.parse(response.body)
      jsono = json.first
      expect(jsono['taxon']['common_name']['name']).to eq tn.name
    end

    it "should include identifications_count" do
      o = Observation.make!
      i = Identification.make!(:observation => o)
      get :index, :format => :json
      obs = JSON.parse(response.body).detect{|jo| jo['id'] == i.observation_id}
      expect(obs['identifications_count']).to eq 1
    end

    it "should include comments_count" do
      c = Comment.make!
      get :index, :format => :json
      obs = JSON.parse(response.body).detect{|o| o['id'] == c.parent_id}
      expect(obs['comments_count']).to eq 1
    end

    it "should let you request project_observations as extra data" do
      po = make_project_observation
      get :index, :format => :json, :extra => "projects"
      obs = JSON.parse(response.body).detect{|o| o['id'] == po.observation_id}
      expect(obs['project_observations']).not_to be_blank
    end

    it "should let you request observation field values as extra data" do
      ofv = ObservationFieldValue.make!
      get :index, :format => :json, :extra => "fields"
      obs = JSON.parse(response.body).detect{|o| o['id'] == ofv.observation_id}
      expect(obs['observation_field_values']).not_to be_blank
    end

    it "should let you request observation_photos as extra data" do
      rgo = make_research_grade_observation
      get :index, :format => :json, :extra => "observation_photos"
      obs = JSON.parse(response.body).detect{|o| o['id'] == rgo.id}
      expect(obs['observation_photos']).not_to be_nil
    end

    it "should let you request identifications as extra data" do
      rgo = make_research_grade_observation
      get :index, :format => :json, :extra => "identifications"
      obs = JSON.parse(response.body).detect{|o| o['id'] == rgo.id}
      obs['identifications'].should_not be_nil
    end

    it "should filter by list_id" do
      l = List.make!
      lt = ListedTaxon.make!(:list => l)
      on_list_obs = Observation.make!(:observed_on_string => "2013-01-03", :taxon => lt.taxon)
      off_list_obs = Observation.make!(:observed_on_string => "2013-01-03", :taxon => Taxon.make!)
      get :index, :format => :json, :on => on_list_obs.observed_on_string, :list_id => l.id
      json_obs = JSON.parse(response.body)
      expect(json_obs.detect{|o| o['id'] == on_list_obs.id}).not_to be_blank
      expect(json_obs.detect{|o| o['id'] == off_list_obs.id}).to be_blank
    end

    it "should not require sign in for page 100 or more" do
      get :index, :format => :json, :page => 101
      expect(response).to be_success
    end

    it "should filter by taxon name" do
      o1 = Observation.make!(:taxon => Taxon.make!)
      o2 = Observation.make!(:taxon => Taxon.make!)
      get :index, :format => :json, :taxon_name => o1.taxon.name
      expect(JSON.parse(response.body).size).to eq 1
    end

    it "should filter by taxon name regardless of case" do
      t = Taxon.make!(name: "Foo bar")
      o1 = Observation.make!(taxon: t)
      o2 = Observation.make!(taxon: Taxon.make!)
      get :index, :format => :json, :taxon_name => "foo bar"
      expect(JSON.parse(response.body).size).to eq 1
    end

    it "should filter by taxon name if there are synonyms and iconic_taxa provided" do
      load_test_taxa
      o1 = Observation.make!(:taxon => @Pseudacris_regilla)
      synonym = Taxon.make!(:parent => @Calypte, :name => o1.taxon.name)
      o2 = Observation.make!(:taxon => synonym)
      get :index, :format => :json, :taxon_name => o1.taxon.name, :iconic_taxa => [@Aves.name]
      expect(JSON.parse(response.body).size).to eq 1
    end

    it "should filter by multiple taxon ids" do
      load_test_taxa
      o1 = Observation.make!(taxon: @Calypte_anna)
      o2 = Observation.make!(taxon: @Pseudacris_regilla)
      o3 = Observation.make!(taxon: Taxon.make!)
      get :index, format: :json, taxon_ids: [@Aves.id, @Amphibia.id]
      json = JSON.parse(response.body)
      expect( json.detect{|o| o['id'] == o1.id} ).not_to be_blank
      expect( json.detect{|o| o['id'] == o2.id} ).not_to be_blank
      expect( json.detect{|o| o['id'] == o3.id} ).to be_blank
    end

    it "should filter by place and multiple taxon ids" do
      load_test_taxa
      place = make_place_with_geom
      in_place_bird = Observation.make!(taxon: @Calypte_anna, latitude: place.latitude, longitude: place.longitude)
      in_place_frog = Observation.make!(taxon: @Pseudacris_regilla, latitude: place.latitude, longitude: place.longitude)
      in_place_other = Observation.make!(taxon: Taxon.make!, latitude: place.latitude, longitude: place.longitude)
      out_of_place_bird = Observation.make!(taxon: @Calypte_anna, latitude: place.latitude*-1, longitude: place.longitude*-1)
      out_of_place_other = Observation.make!(taxon: Taxon.make!, latitude: place.latitude*-1, longitude: place.longitude*-1)
      get :index, format: :json, taxon_ids: [@Aves.id, @Amphibia.id], place_id: place.id
      json = JSON.parse(response.body)
      expect( json.detect{|o| o['id'] == in_place_bird.id} ).not_to be_blank
      expect( json.detect{|o| o['id'] == in_place_frog.id} ).not_to be_blank
      expect( json.detect{|o| o['id'] == in_place_other.id} ).to be_blank
      expect( json.detect{|o| o['id'] == out_of_place_bird.id} ).to be_blank
      expect( json.detect{|o| o['id'] == out_of_place_other.id} ).to be_blank
    end

    it "should filter by mappable = true" do
      Observation.make!
      Observation.make!
      Observation.make!(:latitude => 1.2, :longitude => 2.2)
      get :index, :format => :json, :mappable => 'true'
      expect(JSON.parse(response.body).count).to eq 1
    end

    it "should filter by mappable = false" do
      Observation.make!
      Observation.make!
      Observation.make!(:latitude => 1.2, :longitude => 2.2)
      get :index, :format => :json, :mappable => 'false'
      expect(JSON.parse(response.body).count).to eq 2
    end

    it "should not filter by mappable when its nil" do
      Observation.make!
      Observation.make!
      Observation.make!(:latitude => 1.2, :longitude => 2.2)
      get :index, :format => :json, :mappable => nil
      expect(JSON.parse(response.body).count).to eq 3
    end

    it "should include place_guess" do
      o = Observation.make!(:place_guess => "my backyard")
      get :index, :format => :json
      expect(response.body).to be =~ /#{o.place_guess}/
    end

    it "should not include place_guess if coordinates obscured" do
      o = Observation.make!(:place_guess => "my backyard", :geoprivacy => Observation::OBSCURED)
      get :index, :format => :json
      expect(response.body).to be =~ /#{o.place_guess}/
    end

    it "should filter by project slug" do
      po = make_project_observation
      get :index, format: :json, projects: po.project.slug
      json = JSON.parse(response.body)
      expect( json.detect{|obs| obs['id'] == po.observation_id} ).not_to be_blank
    end

    it "should filter by observations not in a project" do
      po1 = ProjectObservation.make!
      po2 = ProjectObservation.make!
      get :index, format: :json, not_in_project: po1.project_id
      json = JSON.parse(response.body)
      expect( json.detect{|o| o['id'] == po1.observation_id} ).to be_blank
      expect( json.detect{|o| o['id'] == po2.observation_id} ).not_to be_blank
    end

    it "should filter by identified" do
      identified = Observation.make!(taxon: Taxon.make!)
      unidentified = Observation.make!
      get :index, format: :json, identified: true
      json = JSON.parse(response.body)
      expect( json.detect{|o| o['id'] == unidentified.id} ).to be_blank
      expect( json.detect{|o| o['id'] == identified.id} ).not_to be_blank
    end

    it "should filter by not identified" do
      identified = Observation.make!(taxon: Taxon.make!)
      unidentified = Observation.make!
      get :index, format: :json, identified: false
      json = JSON.parse(response.body)
      expect( json.detect{|o| o['id'] == unidentified.id} ).not_to be_blank
      expect( json.detect{|o| o['id'] == identified.id} ).to be_blank
    end

    it "should allow limit" do
      10.times { Observation.make! }
      get :index, format: :json, limit: 3
      expect( JSON.parse(response.body).size ).to eq 3
    end

    it "filters on observation fields" do
      o = Observation.make!
      of = ObservationField.make!(name: "transect_id")
      ofv = ObservationFieldValue.make!(:observation => o, :observation_field => of, :value => "67-48")
      get :index, format: :json, "field:transect_id" => "67-48"
      expect( JSON.parse(response.body).size ).to eq 1
    end

    it "filters created_on based on utc" do
      Observation.make!(created_at: "2014-12-31 20:00:00 -0800")
      Observation.make!(created_at: "2015-1-1 4:00:00")
      Observation.make!(created_at: "2015-1-2 4:00:00 +0800")
      get :index, format: :json, created_on: "2015-1-1"
      expect( JSON.parse(response.body).size ).to eq 3
    end

    it "observations with no time_observed_at ignore time part of date filters" do
      Observation.make!(observed_on_string: "2014-12-31 20:00:00 -0100")
      Observation.make!(observed_on_string: "2014-12-31")
      get :index, format: :json, d1: "2014-12-31T19:00:00-01:00", d2: "2014-12-31T21:00:00-01:00"
      expect( JSON.parse(response.body).size ).to eq 2
    end
  end

  describe "taxon_stats" do
    before(:each) { enable_elastic_indexing( Observation, Place ) }
    after(:each) { disable_elastic_indexing( Observation, Place ) }
    before do
      @o = Observation.make!(:observed_on_string => "2013-07-20", :taxon => Taxon.make!(:rank => Taxon::SPECIES))
      get :taxon_stats, :format => :json, :on => "2013-07-20"
      @json = JSON.parse(response.body)
    end

    it "should include a total" do
      expect(@json["total"].to_i).to be > 0
    end

    it "should include species_counts" do
      expect(@json["species_counts"].size).to be > 0
    end

    it "should include rank_counts" do
      expect(@json["rank_counts"][@o.taxon.rank.downcase]).to be > 0
    end
  end

  describe "user_stats" do
    before(:each) { enable_elastic_indexing( Observation, Place ) }
    after(:each) { disable_elastic_indexing( Observation, Place ) }
    before do
      @o = Observation.make!(:observed_on_string => "2013-07-20", :taxon => Taxon.make!(:rank => Taxon::SPECIES))
      get :user_stats, :format => :json, :on => "2013-07-20"
      @json = JSON.parse(response.body)
    end

    it "should include a total" do
      expect(@json["total"].to_i).to be > 0
    end

    it "should include most_observations" do
      expect(@json["most_observations"].size).to be > 0
    end

    it "should include most_species" do
      expect(@json["most_species"].size).to be > 0
    end
  end

  describe "viewed_updates" do
    before do
      enable_elastic_indexing(Update)
      without_delay do
        @o = Observation.make!(:user => user)
        @c = Comment.make!(:parent => @o)
        @i = Identification.make!(:observation => @o)
      end
    end
    after(:each) { disable_elastic_indexing(Update) }

    it "should mark all updates from this observation for the signed in user as viewed" do
      num_updates_for_owner = Update.unviewed.activity.where(:resource_type => "Observation", :resource_id => @o.id, :subscriber_id => user.id).count
      expect(num_updates_for_owner).to eq 2
      put :viewed_updates, :format => :json, :id => @o.id
      num_updates_for_owner = Update.unviewed.activity.where(:resource_type => "Observation", :resource_id => @o.id, :subscriber_id => user.id).count
      expect(num_updates_for_owner).to eq 0
    end

    it "should not mark other updates for the signed in user as viewed" do
      without_delay do
        o = Observation.make!(:user => user)
        c = Comment.make!(:parent => o)
      end
      num_updates_for_owner = Update.unviewed.activity.where(:resource_type => "Observation", :subscriber_id => user.id).count
      expect(num_updates_for_owner).to eq 3
      put :viewed_updates, :format => :json, :id => @o.id
      num_updates_for_owner = Update.unviewed.activity.where(:resource_type => "Observation", :subscriber_id => user.id).count
      expect(num_updates_for_owner).to eq 1
    end

    it "should not mark other updates from this observation as viewed" do
      put :viewed_updates, :format => :json, :id => @o.id
      num_updates_for_commenter = Update.unviewed.activity.where(:resource_type => "Observation", :resource_id => @o.id, :subscriber_id => @c.user_id).count
      expect(num_updates_for_commenter).to eq 1
    end
  end

  describe "project" do
    before(:each) { enable_elastic_indexing([ Observation ]) }
    after(:each) { disable_elastic_indexing([ Observation ]) }

    it "should allow filtering by updated_since" do
      pu = ProjectUser.make!
      oldo = Observation.make!(:user => pu.user)
      old_po = ProjectObservation.make!(:observation => oldo, :project => pu.project)
      sleep(2)
      newo = Observation.make!(:user => pu.user)
      new_po = ProjectObservation.make!(:observation => newo, :project => pu.project)
      get :project, :format => :json, :id => pu.project_id, :updated_since => (newo.updated_at - 1.second).iso8601
      json = JSON.parse(response.body)
      expect(json.detect{|o| o['id'] == newo.id}).not_to be_blank
      expect(json.detect{|o| o['id'] == oldo.id}).to be_blank
    end
  end

  describe "update_fields" do
    shared_examples_for "it allows changes" do
      it "should allow ofv creation" do
        put :update_fields, :format => :json, :id => o.id, :observation => {
          :observation_field_values_attributes => {
            "0" => {
              :observation_field_id => of.id,
              :value => "foo"
            }
          }
        }
        expect(response).to be_success
        o.reload
        expect(o.observation_field_values.first.value).to eq "foo"
      end
      it "should allow ofv updating" do
        ofv = ObservationFieldValue.make!(:observation => o, :observation_field => of, :value => "foo")
        put :update_fields, :format => :json, :id => o.id, :observation => {
          :observation_field_values_attributes => {
            "0" => {
              :observation_field_id => of.id,
              :value => "bar"
            }
          }
        }
        expect(response).to be_success
        o.reload
        expect(o.observation_field_values.first.value).to eq "bar"
      end
    end

    describe "for the observer" do
      let(:o) { Observation.make!(:user => user) }
      let(:of) { ObservationField.make! }
      it_behaves_like "it allows changes"
      it "should add to a project when project_id included" do
        p = Project.make!
        pu = ProjectUser.make!(:user => o.user, :project => p)
        put :update_fields, :format => :json, :id => o.id, :project_id => p.id, :observation => {
          :observation_field_values_attributes => {
            "0" => {
              :observation_field_id => of.id,
              :value => "foo"
            }
          }
        }
        expect(ProjectObservation.where(:project_id => p, :observation_id => o).exists?).to be true
      end
    end

    describe "for a non-observer" do
      let(:o) { Observation.make! }
      let(:of) { ObservationField.make! }
      it_behaves_like "it allows changes"
      it "should set the user_id" do
        put :update_fields, :format => :json, :id => o.id, :observation => {
          :observation_field_values_attributes => {
            "0" => {
              :observation_field_id => of.id,
              :value => "foo"
            }
          }
        }
        expect(response).to be_success
        o.reload
        expect(o.observation_field_values.first.user).to eq user
        expect(o.observation_field_values.first.updater).to eq user
      end
    end

    describe "for a curator" do
      before do
        user.roles << Role.make!(:name => "curator")
      end
      let(:o) { Observation.make! }
      let(:of) { ObservationField.make! }

      it "should allow creation if observer prefers editng by curators" do
        u = o.user
        u.update_attributes(:preferred_observation_fields_by => User::PREFERRED_OBSERVATION_FIELDS_BY_CURATORS)
        expect(u.preferred_observation_fields_by).to eq User::PREFERRED_OBSERVATION_FIELDS_BY_CURATORS
        o.reload
        put :update_fields, :format => :json, :id => o.id, :observation => {
          :observation_field_values_attributes => {
            "0" => {
              :observation_field_id => of.id,
              :value => "foo"
            }
          }
        }
        expect(response).to be_success
        o.reload
        expect(o.observation_field_values.first.value).to eq "foo"
      end
      it "should not allow creation if observer prefers editng by observer" do
        o.user.update_attributes(:preferred_observation_fields_by => User::PREFERRED_OBSERVATION_FIELDS_BY_OBSERVER)
        expect(o.user.preferred_observation_fields_by).to eq User::PREFERRED_OBSERVATION_FIELDS_BY_OBSERVER
        put :update_fields, :format => :json, :id => o.id, :observation => {
          :observation_field_values_attributes => {
            "0" => {
              :observation_field_id => of.id,
              :value => "foo"
            }
          }
        }
        expect(response).not_to be_success
        o.reload
        expect(o.observation_field_values).to be_blank
      end
    end
  end
end

describe ObservationsController, "oauth authentication" do
  let(:user) { User.make! }
  let(:token) { double :acceptable? => true, :accessible? => true, :resource_owner_id => user.id, :application => OauthApplication.make! }
  before do
    request.env["HTTP_AUTHORIZATION"] = "Bearer xxx"
    allow(controller).to receive(:doorkeeper_token) { token }
  end
  it_behaves_like "an ObservationsController"
end

describe ObservationsController, "oauth authentication with param" do
  let(:user) { User.make! }
  it "should create" do
    app = OauthApplication.make!
    token = Doorkeeper::AccessToken.create(:application_id => app.id, :resource_owner_id => user.id)
    expect {
      post :create, :format => :json, :access_token => token.token, :observation => {:species_guess => "foo"}
    }.to change(Observation, :count).by(1)
  end
end

describe ObservationsController, "devise authentication" do
  let(:user) { User.make! }
  before do
    http_login(user)
  end
  it_behaves_like "an ObservationsController"
end

describe ObservationsController, "without authentication" do
  describe "index" do
    before(:each) { enable_elastic_indexing([ Observation ]) }
    after(:each) { disable_elastic_indexing([ Observation ]) }
    it "should require sign in for page 100 or more" do
      get :index, :format => :json, :page => 10
      expect(response).to be_success
      get :index, :format => :json, :page => 101
      expect(response.status).to eq 401
    end
  end
end
