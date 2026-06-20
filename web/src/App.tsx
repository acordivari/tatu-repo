import { Outlet, NavLink, useNavigate, useSearchParams } from "react-router-dom";
import { useState } from "react";

function SearchBar() {
  const [params] = useSearchParams();
  const [q, setQ] = useState(params.get("q") ?? "");
  const navigate = useNavigate();

  return (
    <form
      className="searchbar"
      onSubmit={(e) => {
        e.preventDefault();
        navigate(q.trim() ? `/?q=${encodeURIComponent(q.trim())}` : "/");
      }}
    >
      <input
        value={q}
        onChange={(e) => setQ(e.target.value)}
        placeholder="Search artists, cities, regions…"
        aria-label="Search"
      />
      <button type="submit">Search</button>
    </form>
  );
}

export default function App() {
  return (
    <>
      <header className="masthead">
        <div className="masthead-inner">
          <NavLink to="/" className="wordmark" title="Tatu — Artists Around the World">
            Tatu
          </NavLink>
          <SearchBar />
          <nav>
            <NavLink to="/" end>
              Artists
            </NavLink>
            <NavLink to="/shops">Studios</NavLink>
            <NavLink to="/map">Map</NavLink>
            <NavLink to="/review">Review</NavLink>
          </nav>
        </div>
      </header>
      <main>
        <Outlet />
      </main>
    </>
  );
}
