-- load modules
local promise = require "promise" ---@module "deps/promise/promise"
local mutex = require "mutex" ---@module "deps/mutex/mutex"
local spawn = require "coro-spawn"
local prettyPrint = require "pretty-print"
local readline = require "readline"
local discordia = require "discordia"
local utf8 = require "utf8"
local timer = require "timer"

-- make objects
local client = discordia.Client() ---@type Client
local editor = readline.Editor.new()
local remove = table.remove
local config = require "disbucket.config"
local len = utf8.len
local rate = config.rate
local messageFormat = config.messageFormat

-- spawn new process
args[0] = nil
remove(args,1)
local process = spawn("java",{
    stdio = {true,true,true};
    cwd = "./";
    args = args;
})

-- write stdin
local proStdinWrite = process.stdin.write
local function onCommand(err,line,out)
    if out == "SIGINT in readLine" then
        promise.spawn(proStdinWrite,"stop\n")
        return
    end
    promise.spawn(proStdinWrite,{line,"\n"})
    editor:readLine("> ",onCommand)
end
editor:readLine("> ",onCommand)

-- print function
local stdout = prettyPrint.stdout
local stdoutWrite = stdout.write
local function printOut(str)
    stdoutWrite(stdout,{"\27[2K\r\27[0m",str,"> "})
    editor:refreshLine()
end

-- colors
local colors = {
    [".-issued server command:.-"] = "\27[32;1m%s\27[0m";
    [".-joined the game.-"] = "\27[33;1m%s\27[0m";
    [".-left the game.-"] = "\27[33;1m%s\27[0m";
    [".- INFO%]: %[.-%].-"] = "\27[32;1m%s\27[0m";
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
        str = str:gsub("`","\\`")
        lastStr = lastStr .. str
        local content = (messageFormat):format(lastStr)
        if lastMessage and len(content) <= 2000 then
            lastMessage:setContent(content)
        else
            lastStr = str
            lastMessage = channel:send((messageFormat):format(str))
        end
    end

    local function writeMessage(str)
        for pattern,format in pairs(colors) do
            str = str:gsub(pattern,function (this)
                return format:format(this)
            end)
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
                for _,nstr in pairs(now) do
                    rawWriteMessage(nstr)
                end
                messageMutex:unlock()
            else -- 이미 버퍼에 값이 있다면 버퍼에 str 을 더한다
                local lastbuffer = buffer[lenbuffer]
                local newbuffer = lastbuffer .. str
                if len((messageFormat):format(newbuffer)) > 2000 then
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
        if (not member) or (member.bot) then return end
        local messageChannel = message.channel
        if (not messageChannel) or messageChannel ~= channel then return end
        local content = message.content
        if (not content) then return end

        -- 메시지를 지운다
        messageMutex:lock() -- 디스코드 리밋 레이트를 맞추기 위해 메시지 쓰기를 잠금한다
        message:delete() -- 유저 메시지를 지운다
        timer.setTimeout(rate,messageMutex.unlock,messageMutex) -- 디스코드 리밋 레이트 후 잠금 해재한다

        if content:sub(1,1) == "/" then -- 명령어이면
            -- 명령 기록을 남기고 실행한다
            writeMessage(("\27[35mDiscord user '%s' executed '%s'\27[0m\n"):format(member.nickname,content))
            promise.spawn(proStdinWrite,{content,"\n"})
        elseif member:hasRole(role) then
            writeMessage(("\27[35m@%s %s]\27[0m\n"):format(member.name,content))
            promise.spawn(proStdinWrite,{"tellraw @a \"%s\"",content:gsub("\"","\\\""),"\n"})
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
    writeMessage("\27[32;1m[ 서버가 시작되었습니다 ]\27[0m")
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
    writeMessage("\27[31;1m[ 서버가 종료되었습니다 ]\27[0m")
    stdoutWrite(stdout,"\27[2K\r\27[0m[ Process Stopped ]\n")
    timer.setTimeout(1000,os.exit)
end)

client:run(("Bot %s"):format(config.token))
