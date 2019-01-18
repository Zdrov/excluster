defmodule Core.UserServer do
  @moduledoc false

  alias Core.Net

  require Logger

  @hibernate 60_000

  @behaviour :gen_statem

  # Public

  def child_spec([{:id, id} | _] = args) do
    start = {__MODULE__, :start_link, [args]}
    %{id: id, start: start}
  end

  def start_link([{:id, id} | _params] = args) do 
    net_info()

    opts = [
      name: via(id),
      hibernate_after: @hibernate
    ]
    with {:ok, pid} <- :gen_statem.start_link(__MODULE__, args, opts) do
      :sys.statistics(pid, true)
      :sys.trace(pid, true)

      {:ok, pid}
    else
      other -> other
    end
  end

  def get_value(id) do
    [pid | _] = :gproc.lookup_pids(topic(id))
    :gen_statem.call(pid, :read)
  end

  def set_value(id, value) do
    [pid | _] = :gproc.lookup_pids(topic(id))
    :gen_statem.cast(pid, {:write, value})
  end

  def stop(id) do
    [pid | _] = :gproc.lookup_pids(topic(id))
    :gen_statem.stop(pid)
  end

  # Callbacks

  @impl true
  def init([{:id, id} | params] = args) do
    :gproc.reg(topic(id))
    
    {:ok, :init_state, {id, params}}
  end

  @impl true
  def handle_event({:call, from}, :read = params, state, data) do
    actions = [{:reply, from, data}]
    {:keep_state, data, actions}
  end
  def handle_event(:cast, {:write, value} = params, state, data) do
    {:keep_state, value}
  end

  @impl true
  def callback_mode, do: :handle_event_function

  # Private
 
  defp via(id), do: {:via, :gproc, topic(id)}

  defp topic(id), do: {:p, :g, {:user_server, id}}

  defp net_info, do: Net.info |> Kernel.inspect |> Logger.debug
end