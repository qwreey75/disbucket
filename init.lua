local promise = require "promise" ---@module "deps/promise/promise"
local spawn = require "coro-spawn"
local prettyPrint = require "pretty-print"
local readline = require "readline"
local discordia = require "discordia"

local client = discordia.Client() ---@type Client
local editor = readline.Editor.new()
local remove = table.remove
local config = require "config"

-- logger.info(args)
args[0] = nil
remove(args,1)
local process = spawn("java",{
    stdio = {true,true,true};
    cwd = "./";
    args = args;
})

-- write stdin
local proStdinWrite = process.stdin.write
local function onCommand(err,line)
    promise.spawn(proStdinWrite,{line,"\n"})
    editor:readLine("> ",onCommand)
end
editor:readLine("> ",onCommand)

-- print function
local stdout = prettyPrint.stdout
local stdoutWrite = stdout.write
local function printOut(str)
    stdoutWrite(stdout,{"\27[2K\r\27[0m",str,"> "})
end

---check permission function
---@param member Member
local function checkPermission(member)

end
client:once('ready', function ()
    local channel = client:getChannel(config.channelId)
    local guild = client:getGuild(config.guildId)
    local role = guild:getRole(config.roleId)

    -- print stdout and stderr
    local waitter = promise.waitter()
    waitter:add(promise.new(function ()
        for str in process.stdout.read do
            printOut(str)
        end
    end))
    waitter:add(promise.new(function ()
        for str in process.stderr.read do
            printOut(str)
        end
    end))
    waitter:wait()
    process.waitExit()
    stdoutWrite(stdout,"\n[ Process Stopped ]\n")
    os.exit()
end)

client:run(("Bot %s"):format(config.token))
