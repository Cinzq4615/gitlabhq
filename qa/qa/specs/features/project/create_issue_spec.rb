module QA
  describe 'creates issue', :core do
    let(:issue_title) { 'issue title' }

    def create_issue
      Runtime::Browser.visit(:gitlab, Page::Main::Login)
      Page::Main::Login.act { sign_in_using_credentials }

      Factory::Resource::Issue.fabricate! do |issue|
        issue.title = issue_title
      end
    end

    it 'user creates issue' do
      create_issue

      Page::Menu::Side.act { click_issues }

      expect(page).to have_content(issue_title)
    end

    describe 'with attachments', :object_storage do
      let(:file_to_attach) { File.absolute_path(File.join('spec', 'fixtures', 'banana_sample.gif')) }

      it 'user comments on an issue with an attachment' do
        create_issue

        Page::Project::Issue::Show.perform do |show|
          show.comment('See attached banana for scale', attachment: file_to_attach)
        end

        image_url = find('a[href$="banana_sample.gif"]')[:href]

        Page::Project::Issue::Show.perform do |show|
          # Wait for attachment to upload
          found = show.wait(reload: false) do
            show.asset_exists?(image_url)
          end

          expect(found).to be_truthy
        end
      end
    end
  end
end
