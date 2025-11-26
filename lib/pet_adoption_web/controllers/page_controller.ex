defmodule PetAdoptionWeb.PageController do
  use PetAdoptionWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
