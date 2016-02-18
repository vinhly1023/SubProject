class OutpostServer < Sinatra::Base
  set :bind, '0.0.0.0'

  # Input:
  #   + path: /rest/v1/execute
  #   + header: content-type: application/json
  #   + method: POST
  #   + body: JSON data, e.g.
  #   {
  #     "run_id": [Test Central db run id]
  #     "name": "outpost",
  #     "silo": "narnia",
  #     "testsuite": "test suite",
  #     "testcases": "test case 1, test case 2… ",
  #     "config": [config data]
  #   }
  # Output:
  #   http status code: 201
  #   {
  #     [returns status json]
  #   }
  #
  #   http status code: 500
  #   {
  #     "status": false
  #     "message": [Error message]
  #   }
  post '/rest/v1/execute' do
    content_type :json
    begin
      if $outpost_status == 'Running'
        status 500

        return { status: false, message: 'Server is running' }.to_json
      end

      data = JSON.parse request.body.read

      tcs_paths = data['testcases'].split(',').map { |v| "#{data['silo']}/spec/#{data['testsuite']}/#{v.strip}" }

      $outpost_result = "#{Time.now.strftime('%y%m%d_%H%M%S%L')}.json"

      test_data = {
        run_id: data['run_id'],
        email_list: data['email_list'],
        test_cases_paths: tcs_paths,
        session_token: $session,
        web_driver: data['browser'],
        locale: data['locale'],
        env: data['environment'],
        release_day: data['release_day']
      }
      Thread.new { MainActivity.run_tc(test_data) }

      status 201

      { status: true }.to_json

    rescue => e
      puts '*******Error while executing: ' << e.message << "\n" << e.backtrace.join("\n")
      status 500

      { status: false, message: e.to_s }.to_json
    end
  end

  # Input:
  #   + path: /rest/v1/status?silo=narnia
  #   + method: GET
  # Output:
  #   http status code: 200
  #   {
  #     "data": {
  #       "available_test": [
  #         {
  #           "testsuite": "ts1",
  #           "testcases": "tc1, tc2"
  #         },
  #         {
  #           "testsuite": "ts2",
  #           "testcases": "tc1, tc2"
  #         }
  #       ],
  #       "outpost_status": "ready or running or error",
  #       "test_runs": "TBD"
  #     }
  #   }
  #
  #   http status code: 500
  #   {
  #     "message": [Error message]
  #   }
  get '/rest/v1/status' do
    content_type :json

    begin
      silo = params[:silo]
      silo_path = "#{Dir.pwd}/#{silo}"
      testsuites = Dir.glob("**/#{silo}/spec/*").select { |fn| File.directory?(fn) }

      available_test = []

      testsuites.each do |ts|
        testsuite = ts.gsub("#{silo}/spec/", '')
        testcase_path = Dir.glob("**/#{ts}/*").select { |fn| !fn.include?('spec_helper') }
        testcases = testcase_path.map { |x| x.gsub("#{ts}/", '') }.join(',')

        available_test.push(
          testsuite: testsuite,
          testcases: testcases
        )
      end

      result_path = "#{silo_path}/results/#{$outpost_result}"

      if File.exist? result_path
        test_runs = JSON.parse File.read(result_path)
      else
        test_runs = []
      end

      controls = JSON.parse File.read("#{silo_path}/controls.json")

      {
        data: {
          available_test: available_test,
          outpost_status: $outpost_status,
          test_runs: test_runs,
          name: MainActivity::CONST_OUTPOST_NAME,
          parameters: controls['parameters']
        }
      }.to_json

    rescue => e
      puts '*******Error while sending status: ' << e.message << "\n" << e.backtrace.join("\n")
      status 500

      { status: false, outpost_status: 'Error', message: e.to_s }.to_json
    end
  end
end

class MainActivity
  def self.get_config(path)
    CONST_CONFIG_XML.search(path).text
  end

  def self.ip
    Socket.ip_address_list.find { |ai| ai.ipv4? && !ai.ipv4_loopback? }.ip_address
  end

  CONST_HOST_ERROR_MSG = "ERROR: Please check host in config file!\nERROR CODE: %s"
  CONST_SILO_NAME_ERROR_MSG = "\nERROR: Please check the silo name in config file!"
  CONST_CONFIG_XML = Nokogiri::XML File.read("#{Dir.pwd}/config.xml")
  CONST_TEST_CENTRAL_HOST = get_config '//host'
  CONST_SSO_ENDPOINT = "#{CONST_TEST_CENTRAL_HOST}#{get_config '//ssoPath'}"
  CONST_UPLOAD_ENDPOINT = "#{CONST_TEST_CENTRAL_HOST}#{get_config '//uploadPath'}"
  CONST_REGISTER_ENDPOINT = "#{CONST_TEST_CENTRAL_HOST}#{get_config '//register'}"
  CONST_OUTPOST_NAME = get_config '//server/name'
  CONST_OUTPOST_PORT = get_config '//server/port'
  CONST_OUTPOST_HOST = "http://#{ip}:#{CONST_OUTPOST_PORT}"
  CONST_SILO = get_config '//silo/name'

  def self.process
    http_code = TestCentralServices.get_http_code CONST_TEST_CENTRAL_HOST

    return ask CONST_HOST_ERROR_MSG % http_code unless http_code == 200

    say 'You have to login to Test Central to execute test scripts:'

    login_response = login

    return if login_response.nil? || !login_response['status']

    $session = login_response['session']

    register_response = register CONST_OUTPOST_HOST, $session

    return ask register_response['message'] unless register_response['status']

    OutpostServer.run! port: CONST_OUTPOST_PORT

    ask "\n>>> Enter to end the program"
  end

  def self.login
    3.times do
      email = ask('Enter your email:  ')
      password = ask('Enter your password:  ') { |char| char.echo = '*' }

      auth = TestCentralServices.authenticate CONST_SSO_ENDPOINT, email, password

      return auth if auth['status']

      say auth['message']
    end

    nil
  end

  def self.register(host, token)
    return ask CONST_SILO_NAME_ERROR_MSG unless silos.include?(CONST_SILO)

    outpost_name = CONST_OUTPOST_NAME
    outpost_name << Socket.gethostname if outpost_name == ''

    json_data = {
      name: outpost_name,
      silo: CONST_SILO,
      ip: ip,
      status_url: "#{host}/rest/v1/status?silo=#{CONST_SILO}",
      exec_url: "#{host}/rest/v1/execute"
    }

    TestCentralServices.register CONST_REGISTER_ENDPOINT, json_data, token
  end

  def self.run_tc(data)
    $outpost_status = 'Running'

    # TODO -  investigate to use hash for rake task
    system "rake lf_ws[#{data[:test_cases_paths].join('+')},#{data[:session_token]},#{$outpost_result},#{data[:run_id]},#{data[:email_list]},#{data[:env]},#{data[:web_driver]},#{data[:locale]},#{data[:release_day]}]"
    $outpost_status = 'Ready'
    $outpost_result = '_.json'
  end

  def self.silos
    Dir.glob('*').select { |fn| File.directory?(fn) && !fn.include?('lib') }
  end
end

MainActivity.process
