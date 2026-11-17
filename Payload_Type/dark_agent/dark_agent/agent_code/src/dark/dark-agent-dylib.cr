require "./elf/*"
require "./agent/*"
require "./common/*"

# Dylib entry point for Dark Agent
# Crystal runtime is bootstrapped by the __attribute__((constructor)) in crystal_dylib_init.c
# which calls __crystal_main before this export is available.
#
# The loader calls dark_agent_init() after dlopen() to start the agent.
# The agent loop runs on a spawned fiber so the call returns immediately.

fun dark_agent_init : Int32
  log_debug("Starting Dark Agent from dylib...")
  agent = Dark::Agent::Base.new

  # Spawn the agent loop on a fiber so dlopen/caller gets control back
  spawn do
    agent.run
  end

  # Yield to let the scheduler pick up the spawned fiber
  Fiber.yield

  0
end
