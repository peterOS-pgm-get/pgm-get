local Logger = pos.require('logger')
local pgmGet = {
    manifestFilePath = "/os/pgm-get-manifest.json", --- local path to manifest file
    pgmFilePath = "/os/pgms.json", --- local path to program list file
    binPath = "/os/bin/", --- local program intallation path
    binModPath = "os.bin.", --- local program installation module path (for require)
    remoteURL = "https://peter.crall.family/minecraft/cc/pgm-get/", --- Remote repository URL
    gitURL = "https://raw.githubusercontent.com/peterOS-pgm-get/", --- Remote repository URL
    log = Logger('/home/.pgmLog/pgm-get.log'),                      --- Logger
    warnOld = true, --- Warn on old program detected
    manifest = {}, ---@type ProgramData[] --- List of all known programs
    _manifest = {}, ---@type {string: ProgramData} --- Table of all known programs, indexed by program name
    programs = {}, ---@type ProgramData[] --- List of all installed programs
    _programs = {}, ---@type {string: ProgramData} --- Table of all installed programs, indexed by program name
}
if not _G.pgmGet then
    _G.pgmGet = pgmGet
else
    pgmGet = _G.pgmGet
end

local fsOpen = fs.open

---Update the CLI completer
function pgmGet.setCompleter()
    local complete = function(shell, index, arg, args)
        if index == 1 then
            local oprs = { "update", "install", "upgrade", "list", "uninstall" }
            local opt = {}
            for _, opr in pairs(oprs) do
                if string.start(opr, arg) then
                    table.insert(opt, string.sub(opr, string.len(arg) + 1))
                end
            end
            return opt
        elseif index == 2 then
            local opt = {}
            if args[2] == 'install' then
                for _, pgm in pairs(pgmGet.manifest) do
                    if string.start(pgm.program, arg) then
                        table.insert(opt, string.sub(pgm.program, string.len(arg) + 1))
                    end
                end
            elseif args[2] == 'uninstall' then
                for name, _ in pairs(pgmGet._programs) do
                    if pgmGet._manifest[name] and string.start(name, arg) then
                        table.insert(opt, string.sub(name, string.len(arg) + 1))
                    end
                end
            elseif args[2] == 'list' then
                if string.start('installed', arg) then
                    table.insert(opt, string.sub('installed', string.len(arg) + 1))
                end
            end
            return opt
        elseif index == 3 then
            local opt = {}
            if args[2] == 'install' then
                local pgm = pgmGet._manifest[args[3]]
                if pgm and pgm.versions then
                    for _, v in pairs(pgm.versions) do
                        local sv = pgmGet.fixVersionString(v)
                        if string.start(sv, arg) then
                            table.insert(opt, string.sub(sv, string.len(arg) + 1))
                        end
                    end
                end
            end
            return opt
        end
    end
    shell.setCompletionFunction("os/bin/pgm-get/command.lua", complete)
    pgmGet.log:info('Updated CL completer')
end

---Turn manifest and program list into tables indexed by program name
local function toTableManifests()
    local mTable = {}
    for _, pgm in pairs(pgmGet.manifest) do
        mTable[pgm.program] = pgm
    end
    pgmGet._manifest = mTable

    local pTable = {}
    for _, pgm in pairs(pgmGet.programs) do
        pTable[pgm.name] = pgm
    end
    pgmGet._programs = pTable
end

---Initilize pgm-get
---@return boolean succecss
function pgmGet.init(osFsOpen)
    if(osFsOpen) then
        fsOpen = osFsOpen
    end
    if not pgmGet.manifest or #pgmGet.manifest == 0  then
        local f = fs.open(pgmGet.manifestFilePath, 'r')
        if not f then
            pgmGet.log:error('Could not read local manifest file')
            return false
        end
        pgmGet.manifest = textutils.unserialiseJSON(f.readAll()) --- @type ProgramData[]
        f.close()
        if not pgmGet.manifest then
            pgmGet.manifest = {}
            pgmGet.log:error('Local manifest file was corrupted')
            return false
        end
        pgmGet.log:info('Loaded manifest from local file')
    end
    if not pgmGet.programs or #pgmGet.programs == 0 then
        local f = fs.open(pgmGet.pgmFilePath, 'r')
        if not f then
            pgmGet.log:error('Could not read program list file')
            return false
        end
        pgmGet.programs = textutils.unserialiseJSON(f.readAll()) --- @type ProgramData[]
        f.close()
        if not pgmGet.programs then
            pgmGet.log:error('Program list file was corrupted')
            return false
        end
        pgmGet.log:info('Loaded program list from file')
    end
    toTableManifests()
    pgmGet.setCompleter()

    if pgmGet.warnOld then
        pgmGet.updateManifest(true)
    end
    return true
end

---Save the current list of installed programs to file
---@return boolean succecss
function pgmGet.savePgmList()
    if not pgmGet.programs and #pgmGet.programs > 0 then
        return false
    end
    -- toTableManifests()
    local f = fsOpen(pgmGet.pgmFilePath, 'w')
    if not f then
        pgmGet.log:error('Could not write to program list file')
        return false
    end
    pgmGet.programs = {}
    for _,pgm in pairs(pgmGet._programs) do
        table.insert(pgmGet.programs, pgm)
    end
    f.write(textutils.serialiseJSON(pgmGet.programs))
    f.close()
    pgmGet.log:info('Saved program list file')
    return true
end

---Update program manifest from remote
---@return boolean succecss
function pgmGet.updateManifest(warnOld)
    -- if not user.isSu() then
    --     pgmGet.log:warn('Tried to update manifest file, but had insufficient permissions')
    --     return false
    -- end

    local resp, fMsg = http.get(pgmGet.remoteURL .. 'manifest.json')
    if resp == nil then
        pgmGet.log:error('Could not get remote manifest; Timeout')
        return false
    end

    if not (resp.getResponseCode() == 200) then
        pgmGet.log:error('Could not get remote manifest; Response code ' .. resp.getResponseCode())
        return false
    end

    local manifestPlainText = resp.readAll()
    local manifest = textutils.unserialiseJSON(manifestPlainText)
    if not manifest then
        pgmGet.log:error('New manifest file was corrupted')
        return false
    end
    local f = fsOpen(pgmGet.manifestFilePath, "w")
    if not f then
        pgmGet.log:error('Could not store new local manifest; Could not write to file')
        return false
    end
    f.write(manifestPlainText)
    f.close()
    pgmGet.manifest = manifest

    pgmGet.setCompleter()
    pgmGet.log:info('Updated manifest from remote')
    toTableManifests()

    if warnOld then
        local old = false
        for name, pgm in pairs(pgmGet._programs) do
            if pgmGet._manifest[name] and pgmGet._manifest[name].version > pgm.version and (not pgm.forcedVersion) then
                old = true
                print("Program " ..
                name ..
                " is out of date. Installed version: " ..
                pgmGet.fixVersionString(pgm.version) ..
                ", Latest: " .. pgmGet.fixVersionString(pgmGet._manifest[name].version))
            end
        end
        if old then
            print("Use pgm-get upgrade to upgrade all programs")
            print("Or use pmg-get install [program] to upgrade specific ones")
        end
    end

    return true
end

---Get program data from installed program list.
---Returns nil if the program is not installed
---@param program string program name
---@return table|nil data program data, includding version, files, options and more
function pgmGet.getPgmData(program)
    if not pgmGet.programs then
        if not pgmGet.init() then
            return nil
        end
    end
    return pgmGet._programs[program]
end

---Get program data from manifest
---Returns nil if it an invalid program name
---@param program string program name
---@return ProgramData|nil program data, including version, files, options, and more
function pgmGet.getManifestPgmData(program)
    if not pgmGet.manifest then
        if not pgmGet.init() then
            return nil
        end
    end
    return pgmGet._manifest[program]
end

---Fixes a version string to include trailling zeros for whole numbers
---@param version number version number
---@return string version version as proper string
function pgmGet.fixVersionString(version)
    local vString = version .. ''
    if math.floor(version) == version then
        vString = vString .. '.0'
    end
    return vString
end

---Install a program from remote
---@param program string program name
---@param version string|number|nil program version (use nil or 'latest' to install latest without forcing version)
---@param toShell boolean|nil if status should be printed to the shell (defaults for false)
---@return boolean success if the program was installed
---@return string|nil error description of error encounted, if any
function pgmGet.install(program, version, toShell)
    local pts = function(msg)
        if toShell then
            print(msg)
        end
    end
    if not user.isSu() then
        pgmGet.log:warn('Tried to install ' .. program .. ', but had insufficient permissions')
        return false, 'Insufficient Permissions'
    end
    if not pgmGet.manifest then
        if not pgmGet.init() then
            return false, 'Could not get local manifest'
        end
    end
    local mProgram = pgmGet.getManifestPgmData(program)
    if not mProgram then
        pgmGet.log:warn('Tried to install unknown program: "' .. program .. '"')
        return false, 'Unknown program'
    end
    -- local mProgram = pgmGet.manifest[program]
    local baseURI = pgmGet.remoteURL .. program .. '/'
    if mProgram.url then
        baseURI = mProgram.url
    end

    local forcedVersion = false
    version = version or 'latest'
    if version == 'latest' then
        version = mProgram.version
    else
        local v = tonumber(version)
        if not v then
            return false, 'Version must be a number'
        end
        version = v
        forcedVersion = true
    end
    local vString = pgmGet.fixVersionString(version)

    if mProgram.git then
        if version == 'latest' then
            baseURI = pgmGet.gitURL .. ('%s/master/'):format(program)
        else
            baseURI = pgmGet.gitURL .. ('%s/v%s/'):format(program, vString)
        end
    elseif mProgram.versions then
        local hasVersion = false
        for _, v in pairs(mProgram.versions) do
            if v == version then
                hasVersion = true
            end
        end
        if not hasVersion then
            pgmGet.log:error('Tried to install ' .. program .. ' with invalid version: ' .. version)
            return false, 'Invalid version'
        end
        baseURI = baseURI .. vString .. '/'
    end

    if mProgram.versions or mProgram.git then
        local resp, fMsg = http.get(baseURI .. 'manifest.json')
        if resp == nil then
            pgmGet.log:error('Could not get sub manifest; Timeout')
            return false, "Could not get sub manifest; Timeout"
        end

        if not (resp.getResponseCode() == 200) then
            pgmGet.log:error('Could not get sub manifest; Response code ' .. resp.getResponseCode())
            return false, 'Could not get sub manifest; Response code ' .. resp.getResponseCode()
        end

        local manifestPlainText = resp.readAll()
        local pgmManifest = textutils.unserialiseJSON(manifestPlainText)
        if not pgmManifest then
            pgmGet.log:error('Sub manifest file was corrupted')
            return false, 'Could not get sub manifest'
        end
        mProgram.files = pgmManifest.files
        mProgram.cmpt = pgmManifest.cmpt
        mProgram.exec = pgmManifest.exec
        mProgram.startup = pgmManifest.startup
        pgmGet.log:info('Got sub manifest')
    end

    pts('Installing ' .. program .. ' v' .. vString)

    pts('Downloading files . . .')
    for _, file in pairs(mProgram.files) do
        pts('- ' .. file)
        pgmGet.log:debug('Downloading file ' .. file)
        local resp, fMsg = http.get(baseURI .. file)
        if resp == nil then
            pgmGet.log:error("HTTP error; Timeout")
            return false, 'HTTP Error; Timeout'
        end

        if not (resp.getResponseCode() == 200) then
            pgmGet.log:error("HTTP error " .. resp.getResponseCode())
            return false, "HTTP error " .. resp.getResponseCode()
        end
        local f = fs.open(pgmGet.binPath .. program .. '/' .. file, "w")
        if not f then
            pgmGet.log:error('Could not write to file ' .. file)
            return false, 'Could not write to file ' .. file
        end
        f.write(resp.readAll())
        f.close()
    end
    pts('All files downloaded')
    pgmGet.log:info('All files downloaded')

    local pgmListData = {
        name = program,
        exec = mProgram.exec,
        cmpt = mProgram.cmpt,
        startup = mProgram.startup,
        version = version,
        forcedVersion = forcedVersion,
    }
    -- pgmGet.programs[program] = pgmListData
    -- local pgmI = -1
    -- for i, pgm in pairs(pgmGet.programs) do
    --     if pgm.name == program then
    --         pgmI = i
    --         break
    --     end
    -- end
    -- if pgmI >= 0 then
    --     pgmGet.programs[pgmI] = pgmListData
    -- else
    --     table.insert(pgmGet.programs, pgmListData)
    -- end
    pgmGet._programs[program] = pgmListData
    if not pgmGet.savePgmList() then
        return false, 'Could not save program list'
    end

    shell.setAlias(program, pgmGet.binPath .. program .. "/" .. mProgram.exec)
    if mProgram.cmpt then
        if _G.pos then
            shell.setCompletionFunction(pgmGet.binPath .. program .. "/" .. mProgram.exec,
                pos.require(pgmGet.binModPath .. program .. "." .. mProgram.cmpt).complete)
        end
        pts('Set completer')
    end
    if mProgram.startup then
        if type(mProgram.startup) == 'table' then
            local startup = mProgram.startup ---@cast startup string[]
            for _, file in pairs(startup) do
                shell.run(pgmGet.binPath .. program .. "/" .. file)
            end
        else
            shell.run(pgmGet.binPath .. program .. "/" .. mProgram.startup)
        end
        pts('Ran program startup files')
    end

    pgmGet.log:info(program .. ' successfully installed')
    pts(program .. ' successfully installed')
    return true, nil
end

---Upgrade all programs if possible
---@param toShell boolean if status should be printed to shell
---@return boolean success if upgrade did not encounter any erorrs
---@return string|nil error description of error encounted, if any
function pgmGet.upgrade(toShell)
    local pts = function(msg)
        if toShell then
            print(msg)
        end
    end
    if not user.isSu() then
        pgmGet.log:warn('Tried to upgrade programs, but had insufficient permissions')
        return false, 'Insufficient Permissions'
    end
    if not pgmGet.manifest or not pgmGet.programs then
        if not pgmGet.init() then
            return false, 'Could not get local manifest or program list'
        end
    end

    pts('Checking all programs and upgrading')
    local pgmUpdated = 0
    for _, program in pairs(pgmGet.programs) do
        local mProgram = pgmGet.getManifestPgmData(program.name)
        if mProgram and not program.forcedVersion and program.version < mProgram.version then
            if pgmGet.install(program.name, 'latest', toShell) then
                pgmUpdated = pgmUpdated + 1
            end
        end
        if mProgram then
            program.isLocal = false
        else
            program.isLocal = true
        end
    end
    pts(pgmUpdated .. ' programs upgraded')

    return true, nil
end

---Uninstall a program, and remove it from local registry
---@param program string program name
---@return boolean success if the program was uninstalled
---@return string|nil error description of error encounted, if any
function pgmGet.uninstall(program, toShell)
    local pts = function(msg)
        if toShell then
            print(msg)
        end
    end
    pts('Uninstalling '..program)
    pgmGet.log:info('Uninstalling '..program)
    if not user.isSu() then
        pgmGet.log:warn('Tried to uninstall ' .. program .. ', but had insufficient permissions')
        return false, 'Insufficient Permissions'
    end
    if not pgmGet._manifest[program] or not pgmGet._programs[program] then
        pgmGet.log:warn('Tried to uninstall ' .. program .. ', unknown program, or program not installed')
        return false, 'Unknown program, or program not installed'
    end

    local path = pgmGet.binPath .. program .. '/'
    local files = fs.list(path) ---@cast files string[]
    
    pts('Deleting files under '..path..' . . .')
    for i, file in pairs(files) do
        local percent = (i-1) / #files
        pts('- '..math.floor(percent*100)..'% ' .. file)
        fs.delete(path .. file)
    end
    pts('100% - All files deleted')

    pts('Program ' .. program .. ' uninstalled')
    pgmGet.log:info('Program '..program..' uninstalled')
    
    -- pgmGet._programs[program] = nil
    -- for i,pgm in pairs(pgmGet.programs) do
    --     if pgm.program == program then
    --         table.remove(pgmGet.programs, i)
    --         break
    --     end
    -- end
    pgmGet._programs[program] = nil

    if not pgmGet.savePgmList() then
        return false, 'Could not save program list'
    end

    return true, nil
end

---@class ProgramData
---@field program string (Manifest only) Program name
---@field name string (Local only) Program name
---@field version number Version number
---@field files string[] List of files for program
---@field url nil|string Alternent remote repository base url
---@field cmpt nil|string CLI completer file
---@field exec nil|string CLI script
---@field startup nil|string|string[] Startup file(s)
---@field isLocal nil|boolean (Local manifest only) If the program is not from a remote