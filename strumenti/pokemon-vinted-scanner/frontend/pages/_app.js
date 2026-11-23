import "../styles/globals.css";
import Nav from "../components/Nav";

export default function App({ Component, pageProps }) {
  return (
    <div className="app-shell">
      <Nav />
      <main className="app-main">
        <Component {...pageProps} />
      </main>
    </div>
  );
}
