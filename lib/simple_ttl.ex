defmodule SimpleTTL do
  use GenServer

  def start_link(table, ttl, check_interval, typea \\ :set) do
    GenServer.start_link(__MODULE__, %{table: table, ttl: ttl, check_interval: check_interval},
      name: table
    )
  end

  def init(old_args) do
    {type, args} = Map.pop(old_args, :type)
    :ets.new(args.table, [type, :public, :named_table])

    clear(args.table, args.ttl, args.check_interval)
    {:ok, args}
  end

  def delete(cache_id) do
    GenServer.stop(cache_id)
  end

  defdelegate delete(cache_id, key), to: :ets

  defdelegate ets(cache_id), to: :ets, as: :whereis

  def get(cache_id, key) do
    case :ets.lookup(cache_id, key) do
      [] ->
        []

      val ->
        touch(cache_id, key)
        val
    end
  end

  def get_or_store(cache_id, key, store_fun) do
    case :ets.lookup(cache_id, key) do
      [] ->
        result = store_fun.()
        spawn(SimpleTTL, :insert_new, [cache_id, result])
        result

      val ->
        spawn(SimpleTTL, :touch, [cache_id, key])
        val
    end
  end

  def insert_new(cache_id, value) do
    new_value = Tuple.insert_at(value, 1, System.system_time(:seconds))

    :ets.insert_new(cache_id, new_value)
  end

  def new(cache_id, ttl, check_interval, type) do
    %{}
  end

  def put(cache_id, values) when is_list(values) do
    new_values = Enum.map(values, &Tuple.insert_at(&1, 1, System.system_time(:seconds)))

    :ets.insert(cache_id, new_values)
  end

  def put(cache_id, value) do
    new_value = Tuple.insert_at(value, 1, System.system_time(:seconds))

    :ets.insert(cache_id, new_value)
  end

  def touch(cache_id, key) do
    update(cache_id, key, fn x -> x end)
  end

  def update(cache_id, key, update_fun) do
    :ets.update(cache_id, key, fn old ->
      old
      |> Tuple.delete_at(1)
      |> update_fun.()
      |> Tuple.insert_at(1, Systen.system_time(:seconds))
    end)
  end

  def handle_cast(:clear, state) do
    spawn(__MODULE__, :clear, [state.name, state.ttl, state.check_interval])

    {:noreply, state}
  end

  defp clear(table, ttl, check_interval) do
    time = System.system_time(:seconds)

    table
    |> :ets.tab2list()
    |> Enum.each(fn
      entry ->
        if(elem(entry, 1) + ttl < time, do: :ets.delete(table, elem(entry, 0)))
    end)

    Process.sleep(check_interval)
    GenServer.cast(table, :clear)
  end
end
