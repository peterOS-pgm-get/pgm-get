local args = {...}

if #args == 1 then
    if args[1] == "update" then
        print("Updating manifest")
        if not pgmGet.updateManifest(pgmGet.warnOld) then
            printError("Failed to get manifest - Check connection and try again later")
        end
        
        return
    elseif args[1] == "upgrade" then
        local s, e = pgmGet.upgrade(true)
        if not s then
            printError(e)
        end
        return
    elseif args[1] == "list" then
        for _,pgm in pairs(pgmGet.manifest) do
            local str = pgm.program .. ' | Latest: v' .. pgmGet.fixVersionString(pgm.version)
            local program = pgmGet.getPgmData(pgm.program)
            if program then
                str = str .. ' | Installed: v' .. pgmGet.fixVersionString(program.version)
                if program.forcedVersion then
                    str = str .. ' (forced)'
                end
            end
            print(str)
        end
        return
    end
elseif #args >= 2 then
    if args[1] == "install" then
        local pgm = args[2]
        local s, e = pgmGet.install(pgm, args[3], true)
        if not s then
            printError(e)
        end
        return
    elseif args[1] == "uninstall" then
        local pgm = args[2]
        print('Confirm uninstall ' .. pgm.. ' (y/n)')
        if read() ~= 'y' then
            printError('Canceling uninstall')
            return
        end
        local s, e = pgmGet.uninstall(pgm, true)
        if not s then
            printError(e)
        end
        return
    elseif args[1] == "list" and args[2] == "installed" then
        for _,pgm in pairs(pgmGet.programs) do
            local str = pgm.name
            local mProgram = pgmGet.getManifestPgmData(pgm.name)
            if mProgram then
                str = str .. ' | Installed: v' .. pgmGet.fixVersionString(pgm.version)
                if mProgram then
                    str = str .. ' | Latest: v' .. pgmGet.fixVersionString(mProgram.version)
                end
            end
            print(str)
        end
        return
    end
end
print("Invalid Command: pgm-get <update|install> [program]")