-- TAT-2: dump type mappings + headers automatically, then signal completion.
print("[TATAutoDump] loaded, waiting for engine")
ExecuteWithDelay(25000, function()
  print("[TATAutoDump] DumpUSMAP")
  DumpUSMAP()
  print("[TATAutoDump] GenerateSDK")
  pcall(GenerateSDK)
  local f = io.open("TATAutoDump.done", "w"); if f then f:write("ok"); f:close() end
  print("[TATAutoDump] done")
end)
