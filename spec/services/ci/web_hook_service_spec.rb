require 'spec_helper'

describe Ci::WebHookService do
  let(:project) { FactoryGirl.create :project }
  let(:commit)  { FactoryGirl.create :commit, project: project }
  let(:build)   { FactoryGirl.create :build, commit: commit }
  let(:hook)    { FactoryGirl.create :web_hook, project: project }

  describe :execute do
    it "should execute successfully" do
      stub_request(:post, hook.url).to_return(status: 200)
      expect(WebHookService.new.build_end(build)).to be_truthy
    end
  end

  context 'build_data' do
    it "contains all needed fields" do
      expect(build_data(build)).to include(
        :build_id,
        :project_id,
        :ref,
        :build_status,
        :build_started_at,
        :build_finished_at,
        :before_sha,
        :project_name,
        :gitlab_url,
        :build_name
      )
    end
  end

  def build_data(build)
    WebHookService.new.send :build_data, build
  end
end
