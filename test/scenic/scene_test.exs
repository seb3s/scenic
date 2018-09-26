#
#  re-re-Created by Boyd Multerer May 2018.
#  Copyright © 2018 Kry10 Industries. All rights reserved.
#
#

defmodule Scenic.SceneTest do
  use ExUnit.Case, async: false
  doctest Scenic
  alias Scenic.Scene
  alias Scenic.ViewPort.Tables

  import Scenic.Primitives, only: [{:scene_ref, 2}]

  # import IEx

  @not_activated :__not_activated__

  setup do
    {:ok, tables} = Tables.start_link(nil)
    on_exit(fn -> Process.exit(tables, :normal) end)
    %{tables: tables}
  end

  defmodule TestSceneOne do
    use Scenic.Scene
    def init(_, _), do: {:ok, nil}
  end

  defmodule TestSceneTwo do
    use Scenic.Scene
    def init(_, _), do: {:ok, nil}
  end

  # ============================================================================
  # faux module callbacks...

  def init(args, _opts) do
    assert args == [1, 2, 3]
    {:ok, :init_state}
  end

  def handle_info(msg, state) do
    GenServer.cast(self(), {:test_handle_info, msg, state})
    {:noreply, :handle_info_state}
  end

  def handle_set_root(vp, args, state) do
    GenServer.cast(self(), {:test_set_root, vp, args, state})
    {:noreply, :set_root_state}
  end

  def handle_lose_root(vp, state) do
    GenServer.cast(self(), {:test_lose_root, vp, state})
    {:noreply, :lose_root_state}
  end

  def handle_call(msg, from, state) do
    GenServer.cast(self(), {:test_handle_call, msg, from, state})
    {:reply, :handle_call_reply, :handle_call_state}
  end

  def handle_input({:input_noreply, _}, _, _state) do
    {:noreply, :input_noreply_state}
  end

  def handle_input({:input_stop, _}, _, _state) do
    {:stop, :input_stop_state}
  end

  def handle_input({:input_continue, _}, _, _state) do
    {:continue, :input_continue_state}
  end

  def handle_cast(msg, state) do
    GenServer.cast(self(), {:test_handle_cast, msg, state})
    {:noreply, :handle_cast_state}
  end

  # ============================================================================
  # client api

  test "send_event sends an event to a scene by pid" do
    self = self()
    Scene.send_event(self, {:test_event, nil})
    assert_receive({:"$gen_cast", {:event, {:test_event, nil}, ^self}})
  end

  test "cast and cast_to_refs work" do
    # prep the self scene
    scene_ref_0 = make_ref()
    graph_key = {:graph, scene_ref_0, 123}
    registration = {self(), self(), self()}
    Tables.register_scene(scene_ref_0, registration)
    Process.put(:scene_ref, scene_ref_0)

    # start test_scene_1
    scene_ref_1 = make_ref()
    {:ok, pid_scene_1} = GenServer.start(Scene, {TestSceneOne, nil, [scene_ref: scene_ref_1]})
    # prep ref scene 2
    scene_ref_2 = make_ref()
    {:ok, pid_scene_2} = GenServer.start(Scene, {TestSceneOne, nil, [scene_ref: scene_ref_2]})

    # insert the graph we will test later
    graph =
      Scenic.Graph.build()
      |> scene_ref(pid_scene_1)
      |> scene_ref(pid_scene_2)

    Tables.insert_graph(graph_key, self(), graph, %{1 => scene_ref_1, 2 => scene_ref_2})

    # the above are async casts, so sleep to let them run
    # is also why I'm running several different tests in this single test.
    # setup is just to messy
    Process.sleep(100)

    # cast a message by scene_ref
    Scene.cast(scene_ref_0, :test_msg_0)
    assert_receive({:"$gen_cast", :test_msg_0})

    # cast a message by graph_key
    Scene.cast(graph_key, :test_msg_1)
    assert_receive({:"$gen_cast", :test_msg_1})

    # cast to the refs. Graph is explicit
    Scene.cast_to_refs(graph_key, :test_msg_2)
    refute_receive({:"$gen_cast", :test_msg_2})

    # cast to the refs. Graph is implicit
    Scene.cast_to_refs(nil, :test_msg_3)
    refute_receive({:"$gen_cast", :test_msg_3})

    # cleanup
    Process.exit(pid_scene_1, :normal)
    Process.exit(pid_scene_2, :normal)
    Process.delete(:scene_ref)
  end

  test "cast_to_refs casts to self refs raises if not called from a scene" do
    assert_raise RuntimeError, fn ->
      Scene.cast_to_refs(nil, :test_msg)
    end
  end

  # ============================================================================
  # child_spec
  # need a custom child_spec because there can easily be multiple scenes running at the same time
  # they are all really Scenic.Scene as the GenServer module, so need to use differnt ids

  test "child_spec uses the scene module and id - no args" do
    %{
      id: id,
      start: {Scene, :start_link, [__MODULE__, :args, []]},
      type: :worker,
      restart: :permanent,
      shutdown: 500
    } = Scene.child_spec({__MODULE__, :args, []})

    assert is_reference(id)
  end

  # ============================================================================
  test "init stores the scene name in the process dictionary" do
    ref = make_ref()
    Scene.init({__MODULE__, [1, 2, 3], [scene_ref: ref]})
    # verify the process dictionary
    assert Process.get(:scene_ref) == ref
  end

  test "init stores the scene reference in the process dictionary" do
    Scene.init({__MODULE__, [1, 2, 3], [name: :scene_name]})
    # verify the process dictionary
    assert Process.get(:scene_ref) == :scene_name
  end

  test "init sends root_up message if vp_dynamic_root is set" do
    self = self()
    Scene.init({__MODULE__, [1, 2, 3], [name: :scene_name, vp_dynamic_root: self]})
    # verify the message
    assert_receive({:"$gen_cast", {:dyn_root_up, :scene_name, ^self}})
  end

  test "init does not send root_up message if vp_dynamic_root is clear" do
    Scene.init({__MODULE__, [1, 2, 3], [name: :scene_name]})
    # verify the message
    refute_receive({:"$gen_cast", {:dyn_root_up, _, _}})
  end

  test "init stores parent_pid in the process dictionary if set" do
    ref = make_ref()
    Scene.init({__MODULE__, [1, 2, 3], [scene_ref: ref, parent: self()]})
    # verify the process dictionary
    assert Process.get(:parent_pid) == self()
  end

  test "init stores nothing in the process dictionary if parent clear" do
    ref = make_ref()
    Scene.init({__MODULE__, [1, 2, 3], [scene_ref: ref]})
    # verify the process dictionary
    assert Process.get(:parent_pid) == nil
  end

  test "init call mod.init and returns first round of state" do
    self = self()

    {:ok,
     %{
       raw_scene_refs: %{},
       dyn_scene_pids: %{},
       dyn_scene_keys: %{},
       parent_pid: ^self,
       children: %{},
       scene_module: __MODULE__,

       # scene_state: :init_state,
       scene_ref: :scene_name,
       supervisor_pid: nil,
       dynamic_children_pid: nil,
       activation: @not_activated
     }} = Scene.init({__MODULE__, [1, 2, 3], [name: :scene_name, parent: self]})
  end

  # ============================================================================
  # handle_info

  test "handle_info sends unhandled messages to the module" do
    {:noreply, new_state} =
      assert Scene.handle_info(:abc, %{
               scene_module: __MODULE__,
               scene_state: :scene_state
             })

    assert new_state.scene_state == :handle_info_state

    assert_receive({:"$gen_cast", {:test_handle_info, :abc, :scene_state}})
  end

  # ============================================================================
  # handle_call

  test "handle_call sends unhandled messages to mod" do
    self = self()

    {:reply, resp, new_state} =
      assert Scene.handle_call(:other, self, %{
               scene_module: __MODULE__,
               scene_state: :scene_state
             })

    assert resp == :handle_call_reply
    assert new_state.scene_state == :handle_call_state

    assert_receive({:"$gen_cast", {:test_handle_call, :other, ^self, :scene_state}})
  end

  # ============================================================================
  # handle_cast

  test "handle_cast :after_init inits the scene module" do
    scene_ref = make_ref()
    Process.put(:"$ancestors", [self()])

    {:noreply, new_state} =
      assert Scene.handle_cast({:after_init, __MODULE__, [1, 2, 3], []}, %{
               scene_ref: scene_ref
             })

    assert new_state.scene_state == :init_state
  end

  # test "handle_cast :input calls the mod input handler" do
  #   context = %Scenic.ViewPort.Context{
  #     viewport: self()
  #   }

  #   event = {:cursor_enter, 1}
  #   sc_state = :sc_state

  #   {:noreply, new_state} =
  #     assert Scene.handle_cast({:input, event, context}, %{
  #              scene_module: __MODULE__,
  #              scene_state: sc_state,
  #              activation: nil
  #            })

  #   assert new_state.scene_state == :input_state
  #   assert_receive({:"$gen_cast", {:test_input, ^event, ^context, ^sc_state}})
  # end

  test "handle_cast :input calls the mod input handler, which returns noreply" do
    context = %Scenic.ViewPort.Context{
      viewport: self()
    }

    event = {:input_noreply, 1}
    sc_state = :sc_state

    {:noreply, new_state} =
      assert Scene.handle_cast({:input, event, context}, %{
               scene_module: __MODULE__,
               scene_state: sc_state,
               activation: nil
             })

    assert new_state.scene_state == :input_noreply_state
    refute_received({:"$gen_cast", {:continue_input, _}})
  end

  test "handle_cast :input calls the mod input handler, which returns stop" do
    context = %Scenic.ViewPort.Context{
      viewport: self()
    }

    event = {:input_stop, 1}
    sc_state = :sc_state

    {:noreply, new_state} =
      assert Scene.handle_cast({:input, event, context}, %{
               scene_module: __MODULE__,
               scene_state: sc_state,
               activation: nil
             })

    assert new_state.scene_state == :input_stop_state
    refute_received({:"$gen_cast", {:continue_input, _}})
  end

  test "handle_cast :input calls the mod input handler, which returns continue" do
    context = %Scenic.ViewPort.Context{
      viewport: self(),
      raw_input: :raw_input
    }

    event = {:input_continue, 1}
    sc_state = :sc_state

    {:noreply, new_state} =
      assert Scene.handle_cast({:input, event, context}, %{
               scene_module: __MODULE__,
               scene_state: sc_state,
               activation: nil
             })

    assert new_state.scene_state == :input_continue_state
    assert_received({:"$gen_cast", {:continue_input, :raw_input}})
  end

  test "handle_cast unknown calls the mod input handler" do
    {:noreply, new_state} =
      assert Scene.handle_cast(:other, %{
               scene_module: __MODULE__,
               scene_state: :scene_state,
               activation: nil
             })

    assert new_state.scene_state == :handle_cast_state
    assert_receive({:"$gen_cast", {:test_handle_cast, :other, :scene_state}})
  end
end
