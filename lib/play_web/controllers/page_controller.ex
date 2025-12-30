defmodule PlayWeb.PageController do
  use PlayWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
