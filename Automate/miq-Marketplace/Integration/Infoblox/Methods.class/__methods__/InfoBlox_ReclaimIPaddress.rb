#CFME Automate Method: Infoblox_ReclaimPAddress
#
###################################
begin
  # Method for logging
  def log(level, msg, update_message=false)
    $evm.log(level, "#{msg}")
    $evm.root['miq_provision'].message = "#{msg}" if $evm.root['miq_provision'] && update_message
  end

  # dump_root
  def dump_root()
    log(:info, "Root:<$evm.root> Begin $evm.root.attributes")
    $evm.root.attributes.sort.each { |k, v| log(:info, "Root:<$evm.root> Attribute - #{k}: #{v}")} if $evm.root
    log(:info, "Root:<$evm.root> End $evm.root.attributes")
    log(:info, "")
  end

  def call_infoblox(action, ref='record:host', content_type=:xml, body=nil )
    require 'rest_client'
    require 'xmlsimple'
    require 'json'

    servername = nil
    servername ||= $evm.object['servername']

    username = nil
    username ||= $evm.object['username']

    password = nil
    password ||= $evm.object.decrypt('password')

    # if ref is a url then use that one instead
    url = ref if ref.include?('http')
    url ||= "https://#{servername}/wapi/v1.4.1/"+"#{ref}"

    params = {
        :method=>action,
        :url=>url,
        :user=>username,
        :password=>password,
        :headers=>{ :content_type=>content_type, :accept=>:xml }
    }
    content_type == :json ? (params[:payload] = JSON.generate(body) if body) : (params[:payload] = body if body)
    log(:info, "Calling -> Infoblox: #{url} action: #{action} payload: #{params[:payload]}")
    response = RestClient::Request.new(params).execute
    log(:info, "Inspecting response: #{response.inspect}")
    raise "Failure <- Infoblox Response: #{response.code}" unless response.code == 200 || response.code == 201 || response.code == 202 || response.code == 203

    # use XmlSimple to convert xml to ruby hash
    response_hash = XmlSimple.xml_in(response)
    log(:info, "Inspecting response_hash: #{response_hash.inspect}")
    return response_hash
  end

  log(:info, "CFME Automate Method Started", true)


  vm = $evm.root['vm']
  domain_name = $evm.object['dns_domain']


  log(:info, "Releasing IP Address for #{vm.name}.#{domain_name}", true)

  query_name_response = call_infoblox(:get, "record:host?name=#{vm.name}.#{domain_name}")

  name_ref = query_name_response["value"][0]["_ref"][0]


  log(:info, "Releasing ref: #{name_ref}")

  release_ipaddress = call_infoblox(:delete, "#{name_ref}")



  # Exit method
  log(:info, "CFME Automate Method Ended")
  exit MIQ_OK

  # Set Ruby rescue behavior
rescue => err
  log(:error, "[#{err}]\n#{err.backtrace.join("\n")}")
  exit MIQ_STOP
end
