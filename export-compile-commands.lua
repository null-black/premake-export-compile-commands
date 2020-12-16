local p = premake

p.modules.export_compile_commands = {}
local m = p.modules.export_compile_commands

local workspace = p.workspace
local project = p.project

function m.getToolset(cfg)
  return p.tools[cfg.toolset or 'gcc']
end


--This cache is to avoid project include dirs not being included in the command line
--This was the easiest work around I have found thus far
project_include_cache = {}
project_sysinclude_cache = {}

function m.getIncludeDirs(prj, cfg)
  local flags = {}
  for _, dir in ipairs(project_include_cache[prj.name]) do
	--print("include: "..dir)
    table.insert(flags, '-I' .. p.quoted(dir))
  end
  for _, dir in ipairs(project_sysinclude_cache[prj.name]) do
	--print("sysinclude: "..dir)
    table.insert(flags, '-isystem ' .. p.quoted(dir))
  end
  return flags
end


function m.getCommonFlags(prj, cfg)
  local toolset = m.getToolset(cfg)
  local flags = toolset.getcppflags(cfg)
  flags = table.join(flags, toolset.getdefines(cfg.defines))
  flags = table.join(flags, toolset.getundefines(cfg.undefines))
  -- can't use toolset.getincludedirs because some tools that consume
  -- compile_commands.json have problems with relative include paths
  flags = table.join(flags, m.getIncludeDirs(prj, cfg))
  flags = table.join(flags, toolset.getforceincludes(cfg))
  if project.iscpp(prj) then
    flags = table.join(flags, toolset.getcxxflags(cfg))
  else
    flags = table.join(flags, toolset.getcflags(cfg))
  end
  return table.join(flags, cfg.buildoptions)
end

function m.getObjectPath(prj, cfg, node)
  return path.join(cfg.objdir, path.appendExtension(node.objname, '.o'))
end

function m.getDependenciesPath(prj, cfg, node)
  return path.join(cfg.objdir, path.appendExtension(node.objname, '.d'))
end

function m.getFileFlags(prj, cfg, node)
  return table.join(m.getCommonFlags(prj, cfg), {
    '-o', m.getObjectPath(prj, cfg, node),
    '-MF', m.getDependenciesPath(prj, cfg, node),
    '-c', node.abspath
  })
end

function m.generateCompileCommand(prj, cfg, node)
  local toolset = m.getToolset(cfg)
  if project.iscpp(prj) then
    command = toolset.tools['cxx']
  else
    command = toolset.tools['cc']
  end

  return {
    directory = prj.location,
    file = node.abspath,
    command = command .. ' '.. table.concat(m.getFileFlags(prj, cfg, node), ' ')
  }
end

function m.includeFile(prj, node, depth)
  return path.iscppfile(node.abspath)
end

function m.getConfig(prj)
  if _OPTIONS['export-compile-commands-config'] then
    return project.getconfig(prj, _OPTIONS['export-compile-commands-config'],
      _OPTIONS['export-compile-commands-platform'])
  end
  for cfg in project.eachconfig(prj) do
    -- just use the first configuration which is usually "Debug"
    return cfg
  end
end

function m.getProjectCommands(prj, cfg)
  local tr = project.getsourcetree(prj)
  local cmds = {}
  p.tree.traverse(tr, {
    onleaf = function(node, depth)
      if not m.includeFile(prj, node, depth) then
        return
      end
      table.insert(cmds, m.generateCompileCommand(prj, cfg, node))
    end
  })
  return cmds
end

local function writeCfg(wks, fileName, cmds)
  p.generate(wks, fileName, function(wks)
    p.w('[')
    for i = 1, #cmds do
      local item = cmds[i]
      local command = string.format([[
      {
        "directory": "%s",
        "file": "%s",
        "command": "%s"
      }]],
      item.directory,
      item.file,
      item.command:gsub('\\', '\\\\'):gsub('"', '\\"'))
      if i > 1 then
        p.w(',')
      end
      p.w(command)
    end
    p.w(']')
  end) 

end


local function execute()
  for wks in p.global.eachWorkspace() do
    local cfgCmds = {}
    for prj in workspace.eachproject(wks) do
      for cfg in project.eachconfig(prj) do
        local cfgKey = string.format('%s', cfg.shortname)
        if not cfgCmds[cfgKey] then
          cfgCmds[cfgKey] = {}
        end
        cfgCmds[cfgKey] = table.join(cfgCmds[cfgKey], m.getProjectCommands(prj, cfg))
      end
    end

	--Skip running through all configs - we only want one
    --for cfgKey,cmds in pairs(cfgCmds) do
	--  writeCfg(wks, string.format('compile_commands/%s.json', cfgKey), cmds)
    --end
 
    for cfgKey,cmds in pairs(cfgCmds) do
	  writeCfg(wks, string.format('compile_commands.json', cfgKey), cmds)
	  break
    end

  end
end

newaction {
  trigger = 'export-compile-commands',
  description = 'Export compiler commands in JSON Compilation Database Format',
  onProject = function(prj)
		--printf("Gathering includes for project '%s'", prj.name)
		for cfg in project.eachconfig(prj) do
			project_include_cache[prj.name] = prj.includedirs
			project_sysinclude_cache[prj.name] = prj.sysincludedirs
		end
	end,
  execute = execute
}

return m
