local configuration = require('configuration')
local provider = require('provider')
local balancer = require('balancer')
local pcall = pcall

local _M = {
  _VERSION = '0.1'
}

local missing_configuration = os.getenv('APICAST_MISSING_CONFIGURATION') or 'log'

local function handle_missing_configuration(err)
  if missing_configuration == 'log' then
    ngx.log(ngx.ERR, 'failed to load configuration, continuing: ', err)
  elseif missing_configuration == 'exit' then
    ngx.log(ngx.EMERG, 'failed to load configuration, exiting: ', err)
    os.exit(1)
  else
    ngx.log(ngx.ERR, 'unknown value of APICAST_MISSING_CONFIGURATION: ', missing_configuration)
    os.exit(1)
  end
end

function _M.init()
  local config, err = configuration.init()

  if config then
    provider.init(config)
  else
    handle_missing_configuration(err)
  end
end

function _M.init_worker()
  local interval = tonumber(os.getenv('AUTO_UPDATE_INTERVAL'), 10)

  local function schedule(interval, handler)
    local ok, err = ngx.timer.at(interval, handler)

    if not ok then
      ngx.log(ngx.ERR, "failed to create the auto update timer: ", err)
      return
    end
  end

  local handler

  handler = function (premature)
    if premature then return end

    ngx.log(ngx.INFO, 'auto updating configuration')

    local updated, err = pcall(_M.init)

    if updated then
      ngx.log(ngx.INFO, 'auto updating configuration finished successfuly')
    else
      ngx.log(ngx.ERR, 'auto updating configuration failed with: ', err)
    end

    schedule(interval, handler)
  end

  if interval > 0 then
    schedule(interval, handler)
  end
end

function _M.rewrite()
  -- load configuration if not configured
  -- that is useful when lua_code_cache is off
  -- because the module is reloaded and has to be configured again
  if not provider.configured then
    local config = configuration.boot()
    provider.init(config)
  end
end

function _M.post_action()
  provider.post_action()
end

function _M.access()
  local fun = provider.call()
  return fun()
end

function _M.body_filter()
  ngx.ctx.buffered = (ngx.ctx.buffered or "") .. string.sub(ngx.arg[1], 1, 1000)

  if ngx.arg[2] then
    ngx.var.resp_body = ngx.ctx.buffered
  end
end

function _M.header_filter()
  ngx.var.resp_headers = require('cjson').encode(ngx.resp.get_headers())
end

_M.balancer = balancer.call

return _M
