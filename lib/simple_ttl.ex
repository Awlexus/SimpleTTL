defmodule SimpleTTL do
  use GenServer

  @time_unit :milliseconds
  def start_link(table, ttl, check_interval, type \\ :set) do
    GenServer.start_link(
      __MODULE__,
      %{table: table, ttl: ttl, check_interval: check_interval, type: type},
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

  def insert_new(cache_id, values) when is_list(values) do
    new_values = Enum.map(values, &Tuple.insert_at(&1, 1, System.system_time(@time_unit)))

    :ets.insert_new(cache_id, new_values)
  end

  def insert_new(cache_id, value) do
    new_value = Tuple.insert_at(value, 1, System.system_time(@time_unit))

    :ets.insert_new(cache_id, new_value)
  end

  def put(cache_id, values) when is_list(values) do
    new_values = Enum.map(values, &Tuple.insert_at(&1, 1, System.system_time(@time_unit)))

    :ets.insert(cache_id, new_values)
  end

  def put(cache_id, value) do
    new_value = Tuple.insert_at(value, 1, System.system_time(@time_unit))

    :ets.insert(cache_id, new_value)
  end

  def touch(cache_id, key) do
    update(cache_id, key, fn x -> x end)
  end

  def update(cache_id, key, update_fun) do
    new_val =
      :ets.lookup(cache_id, key)
      |> Tuple.delete_at(1)
      |> update_fun.()
      |> Tuple.insert_at(1, System.system_time(@time_unit))

    :ets.insert(cache_id, new_val)
  end

  def handle_cast(:clear, state) do
    spawn(__MODULE__, :clear, [state.table, state.ttl, state.check_interval])

    {:noreply, state}
  end

  def clear(table, ttl, check_interval) do
    time = System.system_time(@time_unit)

    table
    |> :ets.tab2list()
    |> Enum.each(fn
      entry ->
        time_stamp = elem(entry, 1)
        if(time_stamp + ttl < time, do: :ets.delete(table, elem(entry, 0)))
    end)

    :timer.apply_after(check_interval, GenServer, :cast, [table, :clear])
  end
end
