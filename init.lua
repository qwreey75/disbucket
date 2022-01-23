-- load modules
local promise = require "promise" ---@module "deps/promise/promise"
local mutex = require "mutex" ---@module "deps/mutex/mutex"
local spawn = require "coro-spawn"
local prettyPrint = require "pretty-print"
local readline = require "readline"
local discordia = require "discordia"
local utf8 = require "utf8"
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
local client = discordia.Client() ---@type Client
local editor = readline.Editor.new()
local remove = table.remove
local len = utf8.len
local rate = config.rate or 20
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
        -- uv.new_tty(0, true),
        -- uv.new_tty(1, false),
        -- uv.new_tty(2, false)
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
local function printOut(str)
    stdoutWrite(stdout,{"\27[2K\r\27[0m",str,prompt})
    editor:refreshLine()
end

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
    local messageMutex = mutex.new()
    local channel = client:getChannel(config.channelId) ---@type TextChannel
    local guild = client:getGuild(config.guildId)
    local role = guild:getRole(config.roleId)
    local lastStr = ""
    local lastMessage = channel:getLastMessage() ---@type Message
    if lastMessage and lastMessage.author ~= client.user then
        lastMessage = nil
    end
    if lastMessage then
        lastStr = lastMessage.content:match("```ansi\n(.+)```")
    end
    local buffer = {}

    local function rawWriteMessage(str) -- 리밋 레이트 생각 없이 2000 자 제한만 지켜 메시지 쓰기
        str = str:gsub("`","\\`"):gsub("\r","")
        lastStr = (lastStr .. str):gsub("\n.-\27%[2K","\n")
        local content = (messageFormat):format(lastStr)
        if lastMessage and len(content) <= 2000 then
            lastMessage:setContent(content)
        else
            lastStr = str:gsub("\n.-\27%[2K","\n"):gsub("\27%[2K","")
            lastMessage = channel:send((messageFormat):format(str))
        end
    end

    local function bufferClear(now,callback,...)
        for _,str in ipairs(now) do
            rawWriteMessage(str)
            timer.sleep(rate)
        end
        if callback then
            callback(...)
        end
    end
    local function writeMessage(str)
        if not noColor then
            for pattern,format in pairs(colors) do
                str = str:gsub(pattern,function (...)
                    return format:format(...)
                end)
            end
        end

        -- stdout
        printOut(str) -- stdout 에 뿌린다

        -- buffer
        if messageMutex:isLocked() then -- 만약 쓰기가 진행중이면 buffer 에 집어넣는다
            local lenbuffer = #buffer
            if lenbuffer == 0 then -- 버퍼가 비어있다면, 버퍼를 셋업하고 버퍼 비우기를 예약한다
                buffer[1] = str
                messageMutex:lock()
                local now = buffer
                buffer = {}
                promise.spawn(bufferClear,now,messageMutex.unlock,messageMutex)
            else -- 이미 버퍼에 값이 있다면 버퍼에 str 을 더한다
                local lastbuffer = buffer[lenbuffer]
                local newbuffer = lastbuffer .. str
                if len((messageFormat):format((lenbuffer == 1 and lastStr or "") .. newbuffer)) > 2000 then
                    buffer[lenbuffer+1] = str
                else
                    buffer[lenbuffer] = newbuffer
                end
            end
            return
        end

        -- 쓰기가 진행중이지 않다면 쓰기로 잠그고 쓰기를 진행한다
        messageMutex:lock()
        rawWriteMessage(str)
        timer.setTimeout(rate,messageMutex.unlock,messageMutex) -- 디스코드 리밋 레이트 후 잠금 해재한다
    end

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
        messageMutex:lock() -- 디스코드 리밋 레이트를 맞추기 위해 메시지 쓰기를 잠금한다
        message:delete() -- 유저 메시지를 지운다
        timer.setTimeout(rate,messageMutex.unlock,messageMutex) -- 디스코드 리밋 레이트 후 잠금 해재한다

        local name = author.name
        if rawInput then
            if member:hasRole(role) then
                writeMessage(("\27[35mDiscord user '%s' executed '%s'\27[0m\n"):format(name,content))
                promise.spawn(proStdinWrite,{content,"\n"})
            end
            return
        end
        if content:match("/n") then
            return
        elseif content:sub(1,1) == "/" then -- 명령어이면
            -- 명령 기록을 남기고 실행한다
            content = content:sub(2,-1)
            writeMessage(("\27[35mDiscord user '%s' executed '%s'\27[0m\n"):format(name,content))
            promise.spawn(proStdinWrite,{content,"\n"})
            promise.spawn(proStdinWrite,{command:format(name,content:gsub("\\","\\\\"):gsub("\"","\\\"")),"\n"})
        elseif member:hasRole(role) then
            writeMessage(("\27[35m[@%s] %s\27[0m\n"):format(name,content))
            promise.spawn(proStdinWrite,{tellraw:format(name,content:gsub("\\","\\\\"):gsub("\"","\\\"")),"\n"})
        end
    end
    client:on('messageCreate',discordInput)

    local function discordDelete(message)
        if lastMessage == message then
            lastMessage = nil
        end
    end
    client:on('messageDelete',discordDelete)

    -- print stdout and stderr
    writeMessage("\27[32;1m[ 서버가 시작되었습니다 ]\27[0m\n")
    local waitter = promise.waitter()
    waitter:add(promise.new(function ()
        for str in process.stdout.read do
            promise.spawn(writeMessage,str)
        end
    end))
    waitter:add(promise.new(function ()
        for str in process.stderr.read do
            promise.spawn(writeMessage,str)
        end
    end))
    waitter:wait()
    process.waitExit()
    writeMessage("\27[31;1m[ 서버가 종료되었습니다 ]\27[0m\n")
    stdoutWrite(stdout,"\27[2K\r\27[0m[ Process Stopped ]\n")
    timer.setTimeout(1000,os.exit)
end)

client:run(("Bot %s"):format(config.token))
