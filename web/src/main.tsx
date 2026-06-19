import { StrictMode, Suspense, lazy } from "react";
import { createRoot } from "react-dom/client";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { createBrowserRouter, RouterProvider } from "react-router-dom";
import "./index.css";
import App from "./App";
import Home from "./pages/Home";
import ArtistPage from "./pages/ArtistPage";
import Review from "./pages/Review";

// Code-split the map route so MapLibre (~1MB) only loads when the map is opened.
const MapPage = lazy(() => import("./pages/MapPage"));

const queryClient = new QueryClient({
  defaultOptions: { queries: { staleTime: 60_000, retry: 1 } },
});

const router = createBrowserRouter([
  {
    path: "/",
    element: <App />,
    children: [
      { index: true, element: <Home /> },
      { path: "artists/:handle", element: <ArtistPage /> },
      { path: "review", element: <Review /> },
      {
        path: "map",
        element: (
          <Suspense fallback={<div className="notice">Loading map…</div>}>
            <MapPage />
          </Suspense>
        ),
      },
    ],
  },
]);

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <QueryClientProvider client={queryClient}>
      <RouterProvider router={router} />
    </QueryClientProvider>
  </StrictMode>
);
