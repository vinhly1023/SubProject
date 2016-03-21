
require 'active_support'
require 'active_support/core_ext'
require 'json'
require 'nokogiri'dwewewe
require 'open3'
require 'tempfile'
require_relative 'lib/version'
require_relative 'lib/testcentral_services'

CONST_CONFIG_XML = Nokogiri::XML File.read("#{Dir.pwd}/config.xml")
CONST_HOST = CONST_CONFIG_XML.search('//host').text
CONST_UPLOAD_ENDPOINT = "#{CONST_HOST}#{CONST_CONFIG_XML.search('//uploadPath').text}"
CONST_EMAIL_QUEUE_ENDPOINT = "#{CONST_HOST}#{CONST_CONFIG_XML.search('//emailQueue').text}"

def write_result(out_file_name, run_json)
  out_file = File.new(out_file_name, 'w+')
  out_file.puts(run_json.to_json)
  out_file.close
end

def run_task(opts)
  run_id = opts[:run_id]
  silo_name = opts[:silo_name]
  suite_path = opts[:suite_path]
  file_paths = opts[:file_paths]
  suite_description = opts[:suite_description]
  session_token = opts[:session_token]
  result_name = opts[:result_name]

  silo_path = "#{Dir.pwd}/#{silo_name}"
  out_file_name = "#{silo_path}/results/#{result_name}"

  run_json = {
    run_id: run_id,
    user: '',
    email: '',
    silo: silo_name,
    suite_path: suite_path,
    suite_name: suite_description,
    env: opts[:env],
    locale: opts[:locale],
    web_driver: opts[:web_driver],
    release_date: opts[:release_date],
    data_driven_csv: '',
    device_store: nil,
    payment_type: nil,
    inmon_version: '',
    start_datetime: Time.now,
    end_datetime: nil,
    total_cases: file_paths.count,
    total_passed: 0,
    total_failed: 0,
    total_uncertain: 0,
    schedule_info: nil,
    config: nil,
    tc_version: 'testing',#Version.tc_git_version,
    station_name: '',
    cases: []
  }

  file_paths.each do |tc|
    begin
      file_name = "#{tc.split('/')[-1]}"
      case_name = file_name.chomp('.rb').titleize

      # Run script and get json result
      json_temp_file = Tempfile.new(['temp', '.json'])
      output_json_option = "-f LFJsonFormatter -r ./lib/lf_json_formatter -o #{json_temp_file.path}"
      command = "rspec --require rspec/legacy_formatters #{tc} #{output_json_option}"

      case_json = {
        file_name: file_name,
        comment: suite_description,
        total_steps: 1,
        total_failed: 0,
        total_uncertain: 0,
        steps: [{ name: '', steps: [] }],
        name: case_name
      }

      array_index = run_json[:cases].count
      run_json[:cases][array_index] = case_json

      # Write run_json to file
      write_result out_file_name, run_json

      begin
        puts "running test case >>> #{command}"

        stdout_and_stderr_str, status = Open3.capture2e(command)

        puts "status = #{status}\n" + stdout_and_stderr_str if File.zero? json_temp_file
        puts ">>> Ran test case >> #{file_name}"

        run_json[:end_datetime] = Time.now
        raw_json = File.read(json_temp_file.path)
        case_json = case_json.merge(JSON.parse raw_json, symbolize_names: true)
      rescue => e
        full_error = "#{e} \n" + e.backtrace.join("\n")
        puts "run error ! >>> rspec command error >>> #{e}"
        case_json[:error] = full_error
        case_json[:total_uncertain] = 1
        case_json[:total_failed] = 0
        case_json[:total_steps] = 1
      end

      run_json[:cases][array_index] = case_json

      if case_json[:total_failed] > 0
        run_json[:total_failed] += 1
      elsif case_json[:total_uncertain] == 0
        run_json[:total_passed] += 1
      else
        run_json[:total_uncertain] += 1
      end

      # Write run_json to file
      write_result out_file_name, run_json

      total_steps_passed = case_json[:total_steps] - (case_json[:total_failed] + case_json[:total_uncertain])
      puts "ran test case >>> #{tc}, total/pass/fail/uncertain #{case_json[:total_steps]}/#{total_steps_passed}/#{case_json[:total_failed]}/#{case_json[:total_uncertain]}"
    rescue => e
      full_error = "#{e} \n" + e.backtrace.join("\n")
      puts "run error ! >>> unknown error >>> #{full_error}"
    end
  end

  run_json[:end_datetime] = Time.now

  # Write json result to json file
  write_result out_file_name, run_json

  puts 'Finished test run'
  puts '>>> Upload test result to Test Central information'
  puts TestCentralServices.upload_result CONST_UPLOAD_ENDPOINT, run_json, session_token

  puts '>>> Add email queue'
  puts TestCentralServices.add_email_queue CONST_EMAIL_QUEUE_ENDPOINT, session_token, opts[:run_id], opts[:email_list]
end


task :lf_ws, [:file_paths, :session_token, :outpost_result, :run_id, :email_list, :env, :web_driver, :locale, :release_date] do |_t, args|
  file_paths = args[:file_paths].split('+')
  case_info = file_paths[0].split('/')
  file_name = case_info[-1].chomp('.rb')
  suite_path = case_info[-2]
  silo_name = case_info[0]
  suite_description = "#{silo_name.titleize} #{file_name.titleize}"
  session_token = args[:session_token]

  opts = {
    run_id: args[:run_id],
    silo_name: silo_name,
    suite_path: suite_path,
    file_paths: file_paths,
    suite_description: suite_description,
    session_token: session_token,
    email_list: args[:email_list],
    result_name: args[:outpost_result],
    env: args[:env],
    locale: args[:locale],
    web_driver: args[:web_driver],
    release_date: args[:release_date],
  }

  run_task opts
end
