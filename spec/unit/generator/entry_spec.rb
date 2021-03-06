# frozen_string_literal: true

# rubocop:disable Metrics/ModuleLength
module GitHubChangelogGenerator
  RSpec.describe Entry do
    def label(name)
      { "name" => name }
    end

    def issue(title, labels, number = "1", user = { "login" => "user" })
      {
        "title" => "issue #{title}",
        "labels" => labels.map { |l| label(l) },
        "number" => number,
        "html_url" => "https://github.com/owner/repo/issue/#{number}",
        "user" => user
      }
    end

    def pr(title, labels, number = "1", user = { "login" => "user" })
      {
        "pull_request" => true,
        "title" => "pr #{title}",
        "labels" => labels.map { |l| label(l) },
        "number" => number,
        "html_url" => "https://github.com/owner/repo/pull/#{number}",
        "user" => user.merge("html_url" => "https://github.com/#{user['login']}"),
        "merged_at" => Time.now.utc
      }
    end

    def titles_for(issues)
      issues.map { |issue| issue["title"] }
    end

    def default_sections
      %w[enhancements bugs breaking issues]
    end

    # Default to no issues or PRs.
    let(:issues) { [] }
    let(:pull_requests) { [] }

    # Default to standard options minus verbose to avoid output during testing.
    let(:options) do
      Parser.default_options.merge(verbose: false)
    end

    # Mock out fake github fetching for the issues/pull_requests lets and then
    # expose filtering from the GitHubChangelogGenerator::Generator class
    # instance for end-to-end entry testing.
    let(:generator) do
      fake_fetcher = instance_double(
        "fetcher",
        fetch_closed_issues_and_pr: [issues, pull_requests],
        fetch_closed_pull_requests: [],
        fetch_events_async: issues + pull_requests
      )
      allow(GitHubChangelogGenerator::OctoFetcher).to receive(:new).and_return(fake_fetcher)
      generator = GitHubChangelogGenerator::Generator.new(options)
      generator.send(:fetch_issues_and_pr)
      generator
    end
    let(:filtered_issues) do
      generator.instance_variable_get :@issues
    end
    let(:filtered_pull_requests) do
      generator.instance_variable_get :@pull_requests
    end
    let(:entry_sections) do
      subject.send(:create_sections)
      # In normal usage, the entry generation would have received filtered
      # issues and pull requests so replicate that here for ease of testing.
      subject.send(:sort_into_sections, filtered_pull_requests, filtered_issues)
      subject.instance_variable_get :@sections
    end

    describe "#generate_entry_for_tag" do
      let(:issues) do
        [
          issue("no labels", [], "5", "login" => "user1"),
          issue("enhancement", ["enhancement"], "6", "login" => "user2"),
          issue("bug", ["bug"], "7", "login" => "user1"),
          issue("breaking", ["breaking"], "8", "login" => "user5"),
          issue("all the labels", %w[enhancement bug breaking], "9", "login" => "user9"),
          issue("all the labels different order", %w[breaking enhancement bug], "10", "login" => "user5"),
          issue("some unmapped labels", %w[tests-fail bug], "11", "login" => "user5"),
          issue("no mapped labels", %w[docs maintenance], "12", "login" => "user5")
        ]
      end

      let(:pull_requests) do
        [
          pr("no labels", [], "20", "login" => "user1"),
          pr("enhancement", ["enhancement"], "21", "login" => "user5"),
          pr("bug", ["bug"], "22", "login" => "user5"),
          pr("breaking", ["breaking"], "23", "login" => "user5"),
          pr("all the labels", %w[enhancement bug breaking], "24", "login" => "user5"),
          pr("all the labels different order", %w[breaking enhancement bug], "25", "login" => "user5"),
          pr("some unmapped labels", %w[tests-fail bug], "26", "login" => "user5"),
          pr("no mapped labels", %w[docs maintenance], "27", "login" => "user5")
        ]
      end

      subject { described_class.new(options) }
      describe "include issues without labels" do
        let(:options) do
          Parser.default_options.merge(
            user: "owner",
            project: "repo",
            bug_labels: ["bug"],
            enhancement_labels: ["enhancement"],
            breaking_labels: ["breaking"],
            verbose: false
          )
        end

        it "generates a header and body" do
          changelog = <<-CHANGELOG.gsub(/^ {10}/, "")
          ## [1.0.1](https://github.com/owner/repo/tree/1.0.1) (2017-12-04)

          [Full Changelog](https://github.com/owner/repo/compare/1.0.0...1.0.1)

          **Breaking changes:**

          - issue breaking [\\#8](https://github.com/owner/repo/issue/8)
          - issue all the labels [\\#9](https://github.com/owner/repo/issue/9)
          - issue all the labels different order [\\#10](https://github.com/owner/repo/issue/10)
          - pr breaking [\\#23](https://github.com/owner/repo/pull/23) ([user5](https://github.com/user5))
          - pr all the labels [\\#24](https://github.com/owner/repo/pull/24) ([user5](https://github.com/user5))
          - pr all the labels different order [\\#25](https://github.com/owner/repo/pull/25) ([user5](https://github.com/user5))

          **Implemented enhancements:**

          - issue enhancement [\\#6](https://github.com/owner/repo/issue/6)
          - pr enhancement [\\#21](https://github.com/owner/repo/pull/21) ([user5](https://github.com/user5))

          **Fixed bugs:**

          - issue bug [\\#7](https://github.com/owner/repo/issue/7)
          - issue some unmapped labels [\\#11](https://github.com/owner/repo/issue/11)
          - pr bug [\\#22](https://github.com/owner/repo/pull/22) ([user5](https://github.com/user5))
          - pr some unmapped labels [\\#26](https://github.com/owner/repo/pull/26) ([user5](https://github.com/user5))

          **Closed issues:**

          - issue no labels [\\#5](https://github.com/owner/repo/issue/5)
          - issue no mapped labels [\\#12](https://github.com/owner/repo/issue/12)

          **Merged pull requests:**

          - pr no labels [\\#20](https://github.com/owner/repo/pull/20) ([user1](https://github.com/user1))
          - pr no mapped labels [\\#27](https://github.com/owner/repo/pull/27) ([user5](https://github.com/user5))

          CHANGELOG

          expect(subject.generate_entry_for_tag(pull_requests, issues, "1.0.1", "1.0.1", Time.new(2017, 12, 4).utc, "1.0.0")).to eq(changelog)
        end
      end
      describe "exclude issues without labels" do
        let(:options) do
          Parser.default_options.merge(
            user: "owner",
            project: "repo",
            bug_labels: ["bug"],
            enhancement_labels: ["enhancement"],
            breaking_labels: ["breaking"],
            add_pr_wo_labels: false,
            add_issues_wo_labels: false,
            verbose: false
          )
        end

        it "generates a header and body" do
          changelog = <<-CHANGELOG.gsub(/^ {10}/, "")
          ## [1.0.1](https://github.com/owner/repo/tree/1.0.1) (2017-12-04)

          [Full Changelog](https://github.com/owner/repo/compare/1.0.0...1.0.1)

          **Breaking changes:**

          - issue breaking [\\#8](https://github.com/owner/repo/issue/8)
          - issue all the labels [\\#9](https://github.com/owner/repo/issue/9)
          - issue all the labels different order [\\#10](https://github.com/owner/repo/issue/10)
          - pr breaking [\\#23](https://github.com/owner/repo/pull/23) ([user5](https://github.com/user5))
          - pr all the labels [\\#24](https://github.com/owner/repo/pull/24) ([user5](https://github.com/user5))
          - pr all the labels different order [\\#25](https://github.com/owner/repo/pull/25) ([user5](https://github.com/user5))

          **Implemented enhancements:**

          - issue enhancement [\\#6](https://github.com/owner/repo/issue/6)
          - pr enhancement [\\#21](https://github.com/owner/repo/pull/21) ([user5](https://github.com/user5))

          **Fixed bugs:**

          - issue bug [\\#7](https://github.com/owner/repo/issue/7)
          - issue some unmapped labels [\\#11](https://github.com/owner/repo/issue/11)
          - pr bug [\\#22](https://github.com/owner/repo/pull/22) ([user5](https://github.com/user5))
          - pr some unmapped labels [\\#26](https://github.com/owner/repo/pull/26) ([user5](https://github.com/user5))

          **Closed issues:**

          - issue no mapped labels [\\#12](https://github.com/owner/repo/issue/12)

          **Merged pull requests:**

          - pr no mapped labels [\\#27](https://github.com/owner/repo/pull/27) ([user5](https://github.com/user5))

          CHANGELOG

          expect(subject.generate_entry_for_tag(pull_requests, issues, "1.0.1", "1.0.1", Time.new(2017, 12, 4).utc, "1.0.0")).to eq(changelog)
        end
      end
    end
    describe "#parse_sections" do
      before do
        subject { described_class.new }
      end
      context "valid json" do
        let(:sections_string) { "{ \"foo\": { \"prefix\": \"foofix\", \"labels\": [\"test1\", \"test2\"]}, \"bar\": { \"prefix\": \"barfix\", \"labels\": [\"test3\", \"test4\"]}}" }

        let(:sections_array) do
          [
            Section.new(name: "foo", prefix: "foofix", labels: %w[test1 test2]),
            Section.new(name: "bar", prefix: "barfix", labels: %w[test3 test4])
          ]
        end

        it "returns an array with 2 objects" do
          arr = subject.send(:parse_sections, sections_string)
          expect(arr.size).to eq 2
          arr.each { |section| expect(section).to be_an_instance_of Section }
        end

        it "returns correctly constructed sections" do
          require "json"

          sections_json = JSON.parse(sections_string)
          sections_array.each_index do |i|
            aggregate_failures "checks each component" do
              expect(sections_array[i].name).to eq sections_json.first[0]
              expect(sections_array[i].prefix).to eq sections_json.first[1]["prefix"]
              expect(sections_array[i].labels).to eq sections_json.first[1]["labels"]
              expect(sections_array[i].issues).to eq []
            end
            sections_json.shift
          end
        end
      end
      context "hash" do
        let(:sections_hash) do
          {
            enhancements: {
              prefix: "**Enhancements**",
              labels: %w[feature enhancement]
            },
            breaking: {
              prefix: "**Breaking**",
              labels: ["breaking"]
            },
            bugs: {
              prefix: "**Bugs**",
              labels: ["bug"]
            }
          }
        end

        let(:sections_array) do
          [
            Section.new(name: "enhancements", prefix: "**Enhancements**", labels: %w[feature enhancement]),
            Section.new(name: "breaking", prefix: "**Breaking**", labels: ["breaking"]),
            Section.new(name: "bugs", prefix: "**Bugs**", labels: ["bug"])
          ]
        end

        it "returns an array with 3 objects" do
          arr = subject.send(:parse_sections, sections_hash)
          expect(arr.size).to eq 3
          arr.each { |section| expect(section).to be_an_instance_of Section }
        end

        it "returns correctly constructed sections" do
          sections_array.each_index do |i|
            aggregate_failures "checks each component" do
              expect(sections_array[i].name).to eq sections_hash.first[0].to_s
              expect(sections_array[i].prefix).to eq sections_hash.first[1][:prefix]
              expect(sections_array[i].labels).to eq sections_hash.first[1][:labels]
              expect(sections_array[i].issues).to eq []
            end
            sections_hash.shift
          end
        end
      end
    end

    describe "#sort_into_sections" do
      context "default sections" do
        let(:options) do
          Parser.default_options.merge(
            bug_labels: ["bug"],
            enhancement_labels: ["enhancement"],
            breaking_labels: ["breaking"],
            verbose: false
          )
        end

        let(:issues) do
          [
            issue("no labels", []),
            issue("enhancement", ["enhancement"]),
            issue("bug", ["bug"]),
            issue("breaking", ["breaking"]),
            issue("all the labels", %w[enhancement bug breaking]),
            issue("some unmapped labels", %w[tests-fail bug]),
            issue("no mapped labels", %w[docs maintenance]),
            issue("excluded label", %w[wontfix]),
            issue("excluded and included label", %w[breaking wontfix])
          ]
        end

        let(:pull_requests) do
          [
            pr("no labels", []),
            pr("enhancement", ["enhancement"]),
            pr("bug", ["bug"]),
            pr("breaking", ["breaking"]),
            pr("all the labels", %w[enhancement bug breaking]),
            pr("some unmapped labels", %w[tests-fail bug], "15", "login" => "user5"),
            pr("no mapped labels", %w[docs maintenance], "16", "login" => "user5"),
            pr("excluded label", %w[wontfix]),
            pr("excluded and included label", %w[breaking wontfix])
          ]
        end

        subject { described_class.new(options) }

        it "returns 5 sections" do
          expect(entry_sections.size).to eq 5
        end

        it "returns default sections" do
          default_sections.each { |default_section| expect(entry_sections.select { |section| section.name == default_section }.size).to eq 1 }
        end

        it "assigns issues to the correct sections" do
          breaking_section = entry_sections.select { |section| section.name == "breaking" }[0]
          enhancement_section = entry_sections.select { |section| section.name == "enhancements" }[0]
          issue_section = entry_sections.select { |section| section.name == "issues" }[0]
          bug_section = entry_sections.select { |section| section.name == "bugs" }[0]
          merged_section = entry_sections.select { |section| section.name == "merged" }[0]

          expect(titles_for(breaking_section.issues)).to eq(["issue breaking", "issue all the labels", "pr breaking", "pr all the labels"])
          expect(titles_for(enhancement_section.issues)).to eq(["issue enhancement", "pr enhancement"])
          expect(titles_for(issue_section.issues)).to eq(["issue no labels", "issue no mapped labels"])
          expect(titles_for(bug_section.issues)).to eq(["issue bug", "issue some unmapped labels", "pr bug", "pr some unmapped labels"])
          expect(titles_for(merged_section.issues)).to eq(["pr no labels", "pr no mapped labels"])
        end
      end
      context "configure sections and include labels" do
        let(:options) do
          Parser.default_options.merge(
            configure_sections: "{ \"foo\": { \"prefix\": \"foofix\", \"labels\": [\"test1\", \"test2\"]}, \"bar\": { \"prefix\": \"barfix\", \"labels\": [\"test3\", \"test4\"]}}",
            include_labels: %w[test1 test2 test3 test4],
            verbose: false
          )
        end

        let(:issues) do
          [
            issue("no labels", []),
            issue("test1", ["test1"]),
            issue("test3", ["test3"]),
            issue("test4", ["test4"]),
            issue("all the labels", %w[test4 test2 test3 test1]),
            issue("some included labels", %w[unincluded test2]),
            issue("no included labels", %w[unincluded again])
          ]
        end

        let(:pull_requests) do
          [
            pr("no labels", []),
            pr("test1", ["test1"]),
            pr("test3", ["test3"]),
            pr("test4", ["test4"]),
            pr("all the labels", %w[test4 test2 test3 test1]),
            pr("some included labels", %w[unincluded test2]),
            pr("no included labels", %w[unincluded again])
          ]
        end

        subject { described_class.new(options) }

        it "returns 4 sections" do
          expect(entry_sections.size).to eq 4
        end

        it "returns only configured sections" do
          expect(entry_sections.select { |section| section.name == "foo" }.size).to eq 1
          expect(entry_sections.select { |section| section.name == "bar" }.size).to eq 1
        end

        it "assigns issues to the correct sections" do
          foo_section = entry_sections.select { |section| section.name == "foo" }[0]
          bar_section = entry_sections.select { |section| section.name == "bar" }[0]
          issue_section = entry_sections.select { |section| section.name == "issues" }[0]
          merged_section = entry_sections.select { |section| section.name == "merged" }[0]

          aggregate_failures "checks all sections" do
            expect(titles_for(foo_section.issues)).to eq(["issue test1", "issue all the labels", "issue some included labels", "pr test1", "pr all the labels", "pr some included labels"])
            expect(titles_for(bar_section.issues)).to eq(["issue test3", "issue test4", "pr test3", "pr test4"])
            expect(titles_for(merged_section.issues)).to eq(["pr no labels"])
            expect(titles_for(issue_section.issues)).to eq(["issue no labels"])
          end
        end
      end
      context "configure sections and exclude labels" do
        let(:options) do
          Parser.default_options.merge(
            configure_sections: "{ \"foo\": { \"prefix\": \"foofix\", \"labels\": [\"test1\", \"test2\"]}, \"bar\": { \"prefix\": \"barfix\", \"labels\": [\"test3\", \"test4\"]}}",
            exclude_labels: ["excluded"],
            verbose: false
          )
        end

        let(:issues) do
          [
            issue("no labels", []),
            issue("test1", ["test1"]),
            issue("test3", ["test3"]),
            issue("test4", ["test4"]),
            issue("all the labels", %w[test4 test2 test3 test1]),
            issue("some excluded labels", %w[excluded test2]),
            issue("excluded labels", %w[excluded again])
          ]
        end

        let(:pull_requests) do
          [
            pr("no labels", []),
            pr("test1", ["test1"]),
            pr("test3", ["test3"]),
            pr("test4", ["test4"]),
            pr("all the labels", %w[test4 test2 test3 test1]),
            pr("some excluded labels", %w[excluded test2]),
            pr("excluded labels", %w[excluded again])
          ]
        end

        subject { described_class.new(options) }

        it "returns 4 sections" do
          expect(entry_sections.size).to eq 4
        end

        it "returns only configured sections" do
          expect(entry_sections.select { |section| section.name == "foo" }.size).to eq 1
          expect(entry_sections.select { |section| section.name == "bar" }.size).to eq 1
        end

        it "assigns issues to the correct sections" do
          foo_section = entry_sections.select { |section| section.name == "foo" }[0]
          bar_section = entry_sections.select { |section| section.name == "bar" }[0]
          issue_section = entry_sections.select { |section| section.name == "issues" }[0]
          merged_section = entry_sections.select { |section| section.name == "merged" }[0]

          aggregate_failures "checks all sections" do
            expect(titles_for(foo_section.issues)).to eq(["issue test1", "issue all the labels", "pr test1", "pr all the labels"])
            expect(titles_for(bar_section.issues)).to eq(["issue test3", "issue test4", "pr test3", "pr test4"])
            expect(titles_for(merged_section.issues)).to eq(["pr no labels"])
            expect(titles_for(issue_section.issues)).to eq(["issue no labels"])
          end
        end
      end
      context "add sections" do
        let(:options) do
          Parser.default_options.merge(
            bug_labels: ["bug"],
            enhancement_labels: ["enhancement"],
            breaking_labels: ["breaking"],
            add_sections: "{ \"foo\": { \"prefix\": \"foofix\", \"labels\": [\"test1\", \"test2\"]}}",
            verbose: false
          )
        end

        let(:issues) do
          [
            issue("no labels", []),
            issue("test1", ["test1"]),
            issue("bugaboo", ["bug"]),
            issue("all the labels", %w[test1 test2 breaking enhancement bug]),
            issue("default labels first", %w[enhancement bug test1 test2]),
            issue("some excluded labels", %w[wontfix breaking]),
            issue("excluded labels", %w[wontfix again])
          ]
        end

        let(:pull_requests) do
          [
            pr("no labels", []),
            pr("test1", ["test1"]),
            pr("enhance", ["enhancement"]),
            pr("all the labels", %w[test1 test2 breaking enhancement bug]),
            pr("default labels first", %w[enhancement bug test1 test2]),
            pr("some excluded labels", %w[wontfix breaking]),
            pr("excluded labels", %w[wontfix again])
          ]
        end

        subject { described_class.new(options) }

        it "returns 6 sections" do
          expect(entry_sections.size).to eq 6
        end

        it "returns default sections" do
          default_sections.each { |default_section| expect(entry_sections.select { |section| section.name == default_section }.size).to eq 1 }
        end

        it "returns added section" do
          expect(entry_sections.select { |section| section.name == "foo" }.size).to eq 1
        end

        it "assigns issues to the correct sections" do
          foo_section = entry_sections.select { |section| section.name == "foo" }[0]
          breaking_section = entry_sections.select { |section| section.name == "breaking" }[0]
          enhancement_section = entry_sections.select { |section| section.name == "enhancements" }[0]
          bug_section = entry_sections.select { |section| section.name == "bugs" }[0]
          issue_section = entry_sections.select { |section| section.name == "issues" }[0]
          merged_section = entry_sections.select { |section| section.name == "merged" }[0]

          aggregate_failures "checks all sections" do
            expect(titles_for(breaking_section.issues)).to eq(["issue all the labels", "pr all the labels"])
            expect(titles_for(enhancement_section.issues)).to eq(["issue default labels first", "pr enhance", "pr default labels first"])
            expect(titles_for(bug_section.issues)).to eq(["issue bugaboo"])
            expect(titles_for(foo_section.issues)).to eq(["issue test1", "pr test1"])
            expect(titles_for(issue_section.issues)).to eq(["issue no labels"])
            expect(titles_for(merged_section.issues)).to eq(["pr no labels"])
          end
        end
      end
    end
  end
end
# rubocop:enable Metrics/ModuleLength
