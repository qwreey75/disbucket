-- load modules
local promise = require "promise" ---@module "deps/promise/promise"
local mutex = require "mutex" ---@module "deps/mutex/mutex"
local spawn = require "coro-spawn"
local prettyPrint = require "pretty-print"
local readline = require "readline"
local discordia = require "discordia"
local timer = require "timer"
local fs = require "fs"
local json = require "json"

-- load config file
local configFile = fs.readFileSync("disbucket.json")
local config = configFile and json.decode(configFile)
if not config then
    local pass
    pass,config = pcall(require,"./config")
    if not pass then -- config file not found?
        prettyPrint.stdout:write"Could not load config file. Please check your configuration file and try again."
        os.exit(1) -- exit with error code
    end
end

-- make objects
local discordia_enchent = require "discordia_enchent"
local client = discordia.Client() ---@type Client
discordia_enchent.inject(client)
local editor = readline.Editor.new()
local remove = table.remove
local insert = table.insert
local len = string.len
-- local len = utf8.len
local maxLength = config.maxLength or 2000
local rate = config.rate or 30
local rawInput = config.rawInput
local noColor = config.noColor
local stop = config.stop or "stop"
local prompt = config.prompt or "> "
local messageFormat = config.messageFormat or "```ansi\n%s\n```"
local tellraw = config.tellraw or "[{\"color\":\"green\",\"text\":\"[@%s]\"},{\"color\":\"white\",\"text\":\" %s\"}]"
local command = config.command or "[{\"color\":\"gray\",\"text\":\"[@%s] Used : %s\"}]"
tellraw = "tellraw @a " .. tellraw
command = "tellraw @a " .. command

-- spawn new process
args[0] = nil
remove(args,1)
local process = spawn(config.program or "java",{
    stdio = {
        true,true,true
    };
    cwd = "./";
    args = args;
})

-- write stdin
local proStdinWrite = process.stdin.write
local function onCommand(err,line,out)
    if out == "SIGINT in readLine" then
        promise.spawn(proStdinWrite,{stop,"\n"})
        return
    end
    promise.spawn(proStdinWrite,{line,"\n"})
    editor:readLine(prompt,onCommand)
end
editor:readLine(prompt,onCommand)

-- print function
local stdout = prettyPrint.stdout
local stdoutWrite = stdout.write

-- colors
local colors = {
    [".-issued server command: /w .-"] = "\27[32;1m[ Private Message ]\27[0m",
    [".-issued server command: /msg .-"] = "\27[32;1m[ Private Message ]\27[0m",
    [".-issued server command: /tell .-"] = "\27[32;1m[ Private Message ]\27[0m",
    [".-issued server command: /teammsg .-"] = "\27[32;1m[ Private Message ]\27[0m",
    [".-issued server command: /tm .-"] = "\27[32;1m[ Private Message ]\27[0m",
    ["%[.-:.-:.- WARN%]:.-"] = "\27[33;1m%s\27[0m";
    [".-issued server command:.-"] = "\27[32;1m%s\27[0m";
    [".-joined the game.-"] = "\27[33;1m%s\27[0m";
    [".-left the game.-"] = "\27[33;1m%s\27[0m";
    ["(%[.- INFO%]: )(%[.+%])(.-)"] = "%s\27[47;1m%s\27[0m%s";
}

---check permission function
client:once('ready', function ()
    -- make objects
    local channel = client:getChannel(config.channelId) ---@type TextChannel
    local guild = client:getGuild(config.guildId)
    local role = guild:getRole(config.roleId)

    -- get last message from channel
    local lastStr = ""
    local lastMessage = channel:getLastMessage() ---@type Message
    if lastMessage and lastMessage.author ~= client.user then
        lastMessage = nil
    end
    if lastMessage then
        lastStr = lastMessage.content:match("```ansi\n(.+)```")
    end

    -- simple line limit implementation
    local function writeMsgRaw(str)
        local newStr = (lastStr .. str):gsub("\n.-\27%[2K\r?","\n")
        local content = messageFormat:format(newStr)
        if len(content) >= maxLength or (not lastMessage) then
            lastStr = str
            lastMessage = channel:send(messageFormat:format(str))
        else
            lastStr = newStr
            lastMessage:setContent(content)
        end
    end

    -- rate limit / chunk concat implementation
    local buffer = {}
    local writeLock = mutex.new()
    local function writeMsg(str)
        if not noColor then
            for pattern,format in pairs(colors) do
                str = str:gsub(pattern,function (...)
                    return format:format(...)
                end)
            end
        end

        stdoutWrite(stdout,{"\27%[2K\r",str,prompt})
        editor:refreshLine()
        str = str:gsub("`","\\`")

        if writeLock:isLocked() then
            insert(buffer,str)
            if #buffer == 1 then -- bind to when unlocked
                writeLock:lock()
                local now = buffer
                buffer = {}
                local content = ""
                local temp = lastStr
                for _,chunk in ipairs(now) do
                    temp = (temp .. chunk):gsub("\n.-\27%[2K\r?","\n")
                    -- print(len(messageFormat:format(temp)),len(chunk),len(content))
                    if len(messageFormat:format(temp)) >= maxLength then
                        writeMsgRaw(content)
                        content = chunk
                        temp = chunk
                        timer.sleep(rate)
                    else
                        content = content .. chunk
                    end
                end
                writeMsgRaw(content)
                timer.setTimeout(rate,writeLock.unlock,writeLock)
            end
            return
        end

        writeLock:lock()
        writeMsgRaw(str)
        timer.setTimeout(rate,writeLock.unlock,writeLock)
    end

    ---read discord message
    ---@param message Message
    local function discordInput(message) -- 메시지 들어옴 함수
        -- 메시지 오브젝트 필드를 확인한다
        local member = message.member
        local author = message.author
        if (not author) or (not member) or (member.bot) then return end
        local messageChannel = message.channel
        if (not messageChannel) or messageChannel ~= channel then return end
        local content = message.content
        if (not content) then return end

        -- 메시지를 지운다
        writeLock:lock() -- 디스코드 리밋 레이트를 맞추기 위해 메시지 쓰기를 잠금한다
        message:delete() -- 유저 메시지를 지운다
        timer.setTimeout(rate,writeLock.unlock,writeLock) -- 디스코드 리밋 레이트 후 잠금 해재한다

        local name = author.name
        if rawInput then
            if member:hasRole(role) then
                writeMsg(("\27[35mDiscord user '%s' executed '%s'\27[0m\n"):format(name,content))
                promise.spawn(proStdinWrite,{content,"\n"})
            end
            return
        end
        if content:match("/n") then
            return
        elseif content:sub(1,1) == "/" then -- 명령어이면
            -- 명령 기록을 남기고 실행한다
            content = content:sub(2,-1)
            writeMsg(("\27[35mDiscord user '%s' executed '%s'\27[0m\n"):format(name,content))
            promise.spawn(proStdinWrite,{content,"\n"})
            promise.spawn(proStdinWrite,{command:format(name,content:gsub("\\","\\\\"):gsub("\"","\\\"")),"\n"})
        elseif member:hasRole(role) then
            writeMsg(("\27[35m[@%s] %s\27[0m\n"):format(name,content))
            promise.spawn(proStdinWrite,{tellraw:format(name,content:gsub("\\","\\\\"):gsub("\"","\\\"")),"\n"})
        end
    end
    client:on('messageCreate',discordInput)

    -- when discord message deleted
    local function discordDelete(message)
        if lastMessage == message then
            lastMessage = nil
        end
    end
    client:on('messageDelete',discordDelete)

    -- print stdout and stderr
    promise.spawn(writeMsg,"\27[32;1m[ Server started ]\27[0m\n")
    local waitter = promise.waitter()
    local function pipeRead(pipe)
        for str in pipe.read do
            if str:match "\n" then
                for line in str:gmatch "(.-\n)" do
                    promise.spawn(writeMsg,line)
                end
                local last = str:match "\n(.-)$"
                if last and last ~= "" then
                    promise.spawn(writeMsg,last)
                end
            else
                promise.spawn(writeMsg,str)
            end
        end
    end
    waitter:add(promise.new(pipeRead,process.stdout))
    waitter:add(promise.new(pipeRead,process.stderr))

    -- exit
    waitter:wait()
    process.waitExit()
    writeMsg("\27[31;1m[ Server closed ]\27[0m\n")
    stdoutWrite(stdout,"\n")
2927af4b4936b427f2992e594bad
