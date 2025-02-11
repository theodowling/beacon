defmodule Beacon.Loader do
  # Process to handle resource reloading (layouts, pages, and so on),
  # each site has its own process started by the site supervisor.
  @moduledoc false

  use GenServer
  require Logger

  def start_link(config) do
    GenServer.start_link(__MODULE__, config, name: name(config.site))
  end

  def init(config) do
    if Code.ensure_loaded?(Mix.Project) and Mix.env() == :test do
      :skip
    else
      :ok = load_site_from_db(config.site)
    end

    {:ok, config}
  end

  def name(site) do
    Beacon.Registry.via({site, __MODULE__})
  end

  def reload_site(site) when is_atom(site) do
    config = Beacon.Config.fetch!(site)
    GenServer.call(name(config.site), {:reload_site, config.site}, 300_000)
  end

  def reload_page(%Beacon.Pages.Page{} = page) do
    config = Beacon.Config.fetch!(page.site)
    GenServer.call(name(config.site), {:reload_page, page}, 60_000)
  end

  def unload_page(%Beacon.Pages.Page{} = page) do
    config = Beacon.Config.fetch!(page.site)
    GenServer.call(name(config.site), {:unload_page, page}, 60_000)
  end

  @spec reload_module!(module(), Macro.t()) :: :ok
  def reload_module!(module, ast, file \\ "nofile") do
    :code.delete(module)
    :code.purge(module)
    [{^module, _}] = Code.compile_quoted(ast, file)
    {:module, ^module} = Code.ensure_loaded(module)
    :ok
  rescue
    e ->
      reraise Beacon.LoaderError,
              [message: "Failed to load module #{inspect(module)}, got: #{Exception.message(e)}"],
              __STACKTRACE__
  end

  defp load_site_from_db(site) do
    with :ok <- Beacon.RuntimeJS.load(),
         :ok <- load_runtime_css(site),
         :ok <- load_components(site),
         :ok <- load_layouts(site),
         :ok <- load_pages(site),
         :ok <- load_stylesheets(site) do
      :ok
    else
      _ -> raise Beacon.LoaderError, message: "Failed to load resources for site #{site}"
    end
  end

  defp load_runtime_css(site) do
    # too slow to run the css compiler on every test
    if Code.ensure_loaded?(Mix.Project) and Mix.env() == :test do
      :ok
    else
      Beacon.RuntimeCSS.load(site)
    end
  end

  # TODO: replace my_component in favor of https://github.com/BeaconCMS/beacon/issues/84
  defp load_components(site) do
    Beacon.Loader.ComponentModuleLoader.load_components(
      site,
      Beacon.Components.list_components_for_site(site)
    )

    :ok
  end

  defp load_layouts(site) do
    site
    |> Beacon.Layouts.list_layouts_for_site()
    |> Enum.map(fn layout ->
      Task.async(fn -> load_layout(layout) end)
    end)
    |> Task.await_many(60_000)

    :ok
  end

  defp load_layout(layout) do
    {:ok, _ast} = Beacon.Loader.LayoutModuleLoader.load_layout!(layout.site, layout)
    :ok
  end

  defp load_pages(site) do
    site
    |> Beacon.Pages.list_pages_for_site([:events, :helpers])
    |> Enum.map(fn page ->
      Task.async(fn -> load_page(page) end)
    end)
    |> Task.await_many(300_000)

    :ok
  end

  defp load_page(page) do
    {:ok, _ast} = Beacon.Loader.PageModuleLoader.load_page!(page.site, page)
    Beacon.PubSub.broadcast_page_update(page.site, page.path)
    :ok
  end

  defp load_stylesheets(site) do
    Beacon.Loader.StylesheetModuleLoader.load_stylesheets(
      site,
      Beacon.Stylesheets.list_stylesheets_for_site(site)
    )

    :ok
  end

  def layout_module_for_site(site, layout_id) do
    prefix = Macro.camelize("layout_#{layout_id}")
    module_for_site(site, prefix)
  end

  def page_module_for_site(site, page_id) do
    prefix = Macro.camelize("page_#{page_id}")
    module_for_site(site, prefix)
  end

  def component_module_for_site(site) do
    module_for_site(site, "Component")
  end

  def stylesheet_module_for_site(site) do
    module_for_site(site, "Stylesheet")
  end

  defp module_for_site(site, prefix) do
    site_hash = :crypto.hash(:md5, Atom.to_string(site)) |> Base.encode16()
    Module.concat([BeaconWeb.LiveRenderer, "#{prefix}#{site_hash}"])
  end

  # This retry logic exists because a module may be in the process of being reloaded, in which case we want to retry
  def call_function_with_retry(module, function, args, failure_count \\ 0) do
    apply(module, function, args)
  rescue
    e in UndefinedFunctionError ->
      case {failure_count, e} do
        {x, _} when x >= 10 ->
          Logger.debug("Failed to call #{inspect(module)} #{inspect(function)} 10 times.")
          reraise e, __STACKTRACE__

        {_, %UndefinedFunctionError{function: ^function, module: ^module}} ->
          Logger.debug("Failed to call #{inspect(module)} #{inspect(function)} with #{inspect(args)} for the #{failure_count + 1} time. Retrying.")

          :timer.sleep(100 * (failure_count * 2))

          call_function_with_retry(module, function, args, failure_count + 1)

        _ ->
          reraise e, __STACKTRACE__
      end

    _e in FunctionClauseError ->
      error_message = """
      Could not call #{function} for the given path: #{inspect(List.flatten(args))}.

      Make sure you have created a page for this path. Check Pages.create_page!/2 \
      for more info.\
      """

      reraise Beacon.LoaderError, [message: error_message], __STACKTRACE__

    e ->
      reraise e, __STACKTRACE__
  end

  def maybe_import_my_component(_component_module, [] = _functions) do
  end

  def maybe_import_my_component(component_module, functions) do
    # TODO: early return
    {_new_ast, present} =
      Macro.prewalk(functions, false, fn
        {:my_component, _, _} = node, _acc -> {node, true}
        node, true -> {node, true}
        node, false -> {node, false}
      end)

    if present do
      quote do
        import unquote(component_module), only: [my_component: 2]
      end
    end
  end

  def handle_call({:reload_site, site}, _from, config) do
    {:reply, load_site_from_db(site), config}
  end

  def handle_call({:reload_page, %{status: :draft}}, _from, config) do
    {:reply, :skip, config}
  end

  def handle_call({:reload_page, page}, _from, config) do
    page = Beacon.Repo.preload(page, [:layout, :events, :helpers])

    reply =
      with :ok <- load_runtime_css(page.site),
           # TODO: load only used components, depends on https://github.com/BeaconCMS/beacon/issues/84
           :ok <- load_components(page.site),
           :ok <- load_layout(page.layout),
           :ok <- load_page(page),
           :ok <- load_stylesheets(page.site) do
        :ok
      else
        _ -> raise Beacon.LoaderError, message: "Failed to load resources for page #{page.title} of site #{page.site}"
      end

    {:reply, reply, config}
  end

  def handle_call({:unload_page, page}, _from, config) do
    module = page_module_for_site(page.site, page.id)
    :code.delete(module)
    :code.purge(module)
    Beacon.Router.del_page(page.site, page.path)

    {:reply, :ok, config}
  end
end
