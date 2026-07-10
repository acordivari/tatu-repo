import { Link } from "react-router-dom";
import { usePageMeta } from "../usePageMeta";

export default function NotFound() {
  usePageMeta("Page not found");
  return (
    <div className="page notice">
      <h2>Page not found</h2>
      <p>That page doesn&apos;t exist — the link may have a typo, or the page moved.</p>
      <p>
        <Link to="/">Back to the directory</Link>
      </p>
    </div>
  );
}
