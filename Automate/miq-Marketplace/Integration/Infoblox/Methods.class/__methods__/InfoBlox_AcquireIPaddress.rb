###################################
#
# CFME Automate Method: Infoblox_AcquireIPAddress
#
# Notes: This method will request an IP Address from Infoblox and set it to the provisioning object of a VM
# - gem requirements 'rest_client', 'xmlsimple', 'json'
#
# - Parameters for $evm.root['vmdb_object_type'] = 'vm'
#   - $evm.root['dialog_option_0_network_cidr']
#
# - Parameters for $evm.root['vmdb_object_type'] = 'miq_provision'
#   - prov.get_option(:network_cidr) || ws_values[:network_cidr]
#   - I.e. :network_cidr => '192.168.199.0/24'
#
###################################
begin
  # Method for logging
  def log(level, message)
    @method = 'Infoblox_AcquireIPAddress'
    $evm.log(level, "#{@method} - #{message}")
  end

  # dump_root
  def dump_root()
    log(:info, "Root:<$evm.root> Begin $evm.root.attributes")
    $evm.root.attributes.sort.each { |k, v| log(:info, "Root:<$evm.root> Attribute - #{k}: #{v}")}
    log(:info, "Root:<$evm.root> End $evm.root.attributes")
    log(:info, "")
  end

  # call_infoblox
  def call_infoblox(action, ref='network', body_type=:xml, body=nil)
    require 'rest_client'
    require 'xmlsimple'
    require 'json'

    servername = nil || $evm.object['servername']
    username = nil || $evm.object['username']
    password = nil || $evm.object.decrypt('password')
    url = "https://#{servername}/wapi/v1.7.1/"+"#{ref}"

    params = {
        :method=>action,
        :url=>url,
        :user=>username,
        :password=>password,
        :headers=>{ :content_type=>body_type, :accept=>:xml }
    }
    if body_type == :json
      params[:payload] = JSON.generate(body) if body
    else
      params[:payload] = body if body
    end
    log(:info, "Calling -> Infoblox:<#{url}> action:<#{action}> payload:<#{params[:payload]}>")

    response = RestClient::Request.new(params).execute
    log(:info, "Inspectin -> Infoblox response:<#{response.inspect}>")
    unless response.code == 200 || response.code == 201
      raise "Failure <- Infoblox Response:<#{response.code}>"
    else
      log(:info, "Success <- Infoblox Response:<#{response.code}>")
    end
    # use XmlSimple to convert xml to ruby hash
    response_hash = XmlSimple.xml_in(response)
    log(:info, "Inspecting response_hash: #{response_hash.inspect}")
    return response_hash
  end

  # get_network
  def get_network(net)
    log(:info, "Detected network:<#{net}>")
    prov = $evm.root['miq_provision']
    vm_name = prov.get_option(:vm_name).to_s.strip
    case net

      when 'VM Network'
        network_cidr = '10.11.164.0/23'
        netmask = '255.255.254.0'
        gateway = '10.11.165.254'
        domain = 'rdu.salab.redhat.com'
        hostname = "#{vm_name}"

      when 'Test'
        network_cidr ='192.168.10.0/24'
        netmask = '255.255.255.0'
        gateway = ''
        domain = 'rdu.salab.redhat.com'
        hostname = "#{vm_name}-test"



      else
        raise "Invalid network:<#{net}>. Skipping method"
    end

    log(:info, "Detected network:<#{net}> gateway:<#{gateway}> domain:<#{domain}>")
    return network_cidr, netmask, gateway, domain, hostname
  end

  log(:info, "CFME Automate Method Started")

  # dump all root attributes to the log
  dump_root

  prov = $evm.root['miq_provision']
  raise "miq_provision object not found" if prov.nil?

  log(:info, "Provision:<#{prov.id}> Request:<#{prov.miq_provision_request.id}> Type:<#{prov.type}>")

  if prov.options.has_key?(:ws_values)
    ws_values = prov.options[:ws_values]
  end

  #network = prov.options[:vlan]

  network = prov.options[:networks]


  log(:info, "networks: #{network.inspect}")



  netcount = 0
  network.each do |net|
    # Use the network_cidr to determine gateway and domain
    log(:info, "#{net[:network]}")
    network_cidr, netmask, gateway, domain, hostname = get_network("#{net[:network]}")
    network_infoblox = call_infoblox(:get)
    # only pull out the network and the _ref values
    network_infoblox_hash = Hash[*network_infoblox['value'].collect { |x| [x['network'], x['_ref'][0]] }.flatten]
    raise "network_infoblox_hash returned nil" if network_infoblox_hash.nil?
    log(:info, "Inspecting network_infoblox_hash:<#{network_infoblox_hash}>")

    # call Infoblox to get the next available IP Address
    # query for the next available IP address

    body_get_nextip = {:_function => 'next_available_ip', :num => '1'}
    next_ip = call_infoblox(:post, network_infoblox_hash[network_cidr], nil, body_get_nextip)
    log(:info, "#{next_ip}")

    #get the IP Address returned from Infoblox
    ipaddr = next_ip['ips'][0]['list'][0]['value'].first
    log(:info, "Found next_ip:<#{ipaddr}>")

    body_set_recordhost = {
        :name => "#{hostname}.#{domain}",
        :ipv4addrs =>[ {
                           :ipv4addr => "#{ipaddr}",
                           :configure_for_dhcp => false } ],
    }

    record_host = call_infoblox(:post, 'record:host', :json, body_set_recordhost)
    log(:info, "Infoblox returned record_host:<#{record_host}>")

    $evm.log("info", "GetIP --> NIC = #{netcount}")
    $evm.log("info", "GetIP --> IP Address =  #{ipaddr}")
    $evm.log("info", "GetIP -->  Netmask = #{netmask}")
    $evm.log("info", "GetIP -->  Gateway = #{gateway}")
    $evm.log("info", "GetIP -->  dnsname = #{}")


    prov.set_option(:sysprep_spec_override, 'true')
    #prov.set_option(:addr_mode, ["static", "Static"])
    #prov.set_option(:ip_addr, "#{ipaddr}")
    #prov.set_option(:subnet_mask, "#{netmask}")
    #prov.set_option(:gateway, "#{gateway}")
    #prov.set_network_adapter(0, {:network=>net})
    #log(:info,"Provision object updated: [:networks=>#{prov.options[:networks].first.inspect}]")

    if netcount == 0
      prov.set_nic_settings('#{netcount}', {:ip_addr=>ipaddr, :subnet_mask=>netmask, :gateway=>gateway, :addr_mode=>["static", "Static"]})
    else
      prov.set_nic_settings('#{netcount}', {:ip_addr=>ipaddr, :subnet_mask=>netmask, :addr_mode=>["static", "Static"]})
    end
    #log(:info, "Provision object updated: [:ip_addr=>#{prov.options[:ip_addr].inspect},:subnet_mask=>#{prov.options[:subnet_mask].inspect},:gateway=>#{prov.options[:gateway].inspect},:addr_mode=>#{prov.options[:addr_mode].inspect}]")
    $evm.log("info", "GetIP --> #{prov.inspect}")

    netcount += 1
  end

  # Exit method
  log(:info, "CFME Automate Method Ended")
  exit MIQ_OK

    # Set Ruby rescue behavior
rescue => err
  log(:error, "[#{err}]\n#{err.backtrace.join("\n")}")
  exit MIQ_ABORT
end