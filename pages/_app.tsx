import 'styles/global.css';
import { ThemeProvider } from 'next-themes';


export default function App({
  Component,
  pageProps: { session, ...pageProps }
}) {
  return (
      <ThemeProvider attribute="class">
        <Component {...pageProps} />
      </ThemeProvider>
  );
}
