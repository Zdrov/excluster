defmodule Core.ActionServer do
  @moduledoc false

  require Logger

  alias Core.{
    Counters, 
    StateHandoff, 
    Net
  }

  @registry Core.Registry
  @max_messages 1_000
  @shutdown 10_000
  @hibernate 60_000

  use GenServer, restart: :permanent, shutdown: @shutdown

  # Public

  def child_spec([{:id, id} | _] = args) do
    start = {__MODULE__, :start_link, [args]}
    %{id: id, start: start}
  end

  def start_link([{:id, id} | _] = args) do 
    net_info()

    opts = [
      name: via(id), 
      hibernate_after: @hibernate
    ]
    with {:ok, pid} <- GenServer.start_link(__MODULE__, args, opts) do
      :sys.statistics(pid, true)
      :sys.trace(pid, true)

      {:ok, pid}
    else
      other -> other
    end
  end

  def read(id, params) do
    net_info()
    call(id, :read, params)
  end

  def write(id, value) do
    net_info()
    cast(id, :write, value)
  end

  def whereis(id), do: GenServer.whereis(via(id))

  def stop(id), do: GenServer.stop(via(id), :normal)

  # Callbacks

  @impl true
  def init([{:id, id} | _params]) do
    trap_exit()

    {:ok, {id, nil}, {:continue, nil}}
  end

  @impl true
  def handle_continue(_, {id, _}) do
    start_pobox(id)
    state = state_restore(id)

    {:noreply, {id, state}}
  end

  @impl true
  def handle_call({:read, _params}, _, {id, state}) do
    Counters.inc_counter(:read)

    %{value: value} = state
    {:reply, value, {id, state}}
  end

  @impl true
  def handle_cast({:post, {:write, value}}, {id, state}) do
    Counters.inc_counter(:write)

    new_state = put_in(state[:value], value)
    {:noreply, {id, new_state}}
  end

  @impl true
  def terminate(reason, {id, state}) do
    Logger.debug("Terminating #{inspect id} with reason #{inspect reason}")
    StateHandoff.handoff(id, state)
    :ok
  end

  # Private

  defp state_restore(id) do
    id
    |> StateHandoff.pickup
    |> case do
      [] -> %{value: "some value"}
      restored -> restored
    end
  end

  defp via(id), do: {:via, Horde.Registry, {@registry, id}}

  defp net_info, do: Net.info |> Kernel.inspect |> Logger.debug

  defp trap_exit, do: Process.flag(:trap_exit, true)

  defp start_pobox(id), do: {:ok, _} = :pobox.start_link(via(id), @max_messages, :stack)

  defp call(id, type, params), do: GenServer.call(via(id), {type, params})
  
  defp cast(id, type, value), do: :pobox.post(via(id), {type, value})
end