defmodule Beacon.PageField do
  @moduledoc ~S"""
  Add extra fields to pages.

  ## Example

      defmodule MyApp.TagsField do
        use Phoenix.Component
        import BeaconWeb.CoreComponents
        import Ecto.Changeset

        @behaviour Beacon.PageField

        @impl true
        def name, do: :tags

        @impl true
        def type, do: :string

        @impl true
        def render(assigns) do
          ~H\"""
          <.input type="text" label="Tags" field={@field} />
          \"""
        end

        @impl true
        def changeset(data, attrs) do
          data
          |> cast(attrs, [:tags])
          |> validate_required([:tags])
        end
      end

  """

  @optional_callbacks default: 0

  @doc """
  Field identifier. Must be unique per site.
  """
  @callback name :: atom()

  @doc """
  Field type. Can be any value supported by Ecto Schema.
  """
  @callback type :: any()

  @doc """
  Default value for field. Defaults to `nil`.
  """
  @callback default :: any()

  @doc """
  Template to render the field on Admin.
  """
  @callback render(assigns :: Phoenix.LiveView.Socket.assigns()) :: Phoenix.LiveView.Rendered.t()

  @doc """
  Changeset used to validate and save data.
  """
  @callback changeset(
              data :: {Ecto.Changeset.data(), Ecto.Changeset.types()},
              attrs :: %{String.t() => any()},
              metadata :: %{page_changeset: Ecto.Changeset.t()}
            ) :: Ecto.Changeset.t()

  @doc false
  def extra_fields(site, %Phoenix.HTML.Form{} = form, params, errors) when is_map(params) and is_list(errors) do
    mods = Beacon.Config.fetch!(site).extra_page_fields
    do_extra_fields(mods, form, params, errors)
  end

  @doc false
  def do_extra_fields(mods, form, params, errors) do
    errors = traverse_errors(errors)

    Enum.reduce(mods, %{}, fn mod, acc ->
      name = mod.name()
      default = if function_exported?(mod, :default, 0), do: mod.default(), else: nil
      value = Map.get(params, "#{name}", default)
      errors = Map.get(errors, name, [])

      Map.put(acc, name, %Phoenix.HTML.FormField{
        id: "page_extra_#{name}",
        name: "page[extra][#{name}]",
        errors: errors,
        field: name,
        value: value,
        form: form
      })
    end)
  end

  @doc false
  def traverse_errors(errors) when is_list(errors) do
    merge_fields = fn fields ->
      Enum.reduce(fields, %{}, fn {field, error}, acc ->
        Map.update(acc, field, [error], fn e ->
          [error | e]
        end)
      end)
    end

    Enum.reduce(errors, %{}, fn {:extra, {_msg, fields}}, acc ->
      field = fields |> merge_fields.() |> Map.new(fn {k, v} -> {k, Enum.reverse(v)} end)
      Map.merge(acc, field)
    end)
  end

  @doc false
  def apply_changesets(%Ecto.Changeset{} = page_changeset, site, params) when is_atom(site) and is_map(params) do
    mods = Beacon.Config.fetch!(site).extra_page_fields
    do_apply_changesets(mods, page_changeset, params)
  end

  @doc false
  def do_apply_changesets(mods, page_changeset, params) do
    Enum.reduce(mods, page_changeset, fn mod, page_changeset ->
      name = mod.name()
      params = Map.take(params, ["#{name}"])

      type = mod.type()
      types = %{name => type}
      data = {%{}, types}

      field_changeset = mod.changeset(data, params, %{page_changeset: page_changeset})

      case Ecto.Changeset.apply_action(field_changeset, :update) do
        {:ok, field} ->
          value = Map.get(field, name)
          extra = Ecto.Changeset.get_field(page_changeset, :extra) || %{}
          extra = Map.put(extra, "#{name}", value)
          Ecto.Changeset.put_change(page_changeset, :extra, extra)

        {:error, field_changeset} ->
          value = Ecto.Changeset.apply_changes(field_changeset) |> Map.get(name)
          extra = Ecto.Changeset.get_field(page_changeset, :extra) || %{}
          extra = Map.put(extra, "#{name}", value)
          page_changeset = Ecto.Changeset.put_change(page_changeset, :extra, extra)
          Ecto.Changeset.add_error(page_changeset, :extra, "invalid", field_changeset.errors)
      end
    end)
  end
end
