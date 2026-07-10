// Router-level error boundary: rendered in place of the whole tree when a
// route component throws, so an unexpected error never white-screens the app.
export default function ErrorPage() {
  return (
    <div className="page notice" style={{ paddingTop: "4rem", textAlign: "center" }}>
      <h2>Something went wrong</h2>
      <p>An unexpected error broke this page — sorry about that.</p>
      <p>
        <a href="/">Reload the directory</a>
      </p>
    </div>
  );
}
