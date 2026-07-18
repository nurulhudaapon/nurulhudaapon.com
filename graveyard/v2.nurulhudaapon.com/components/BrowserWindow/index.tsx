import styles from './styles.module.css';

function BrowserWindow({ children, minHeight, url, imgSrc }) {
  return (
    <div className="tesst border border-white w-">
      <div className={styles.browserWindow} style={{ minHeight }}>
        <div className={styles.browserWindowHeader}>
          <div className={styles.buttons}>
            <span className={styles.dot} style={{ background: '#f25f58' }} />
            <span className={styles.dot} style={{ background: '#fbbe3c' }} />
            <span className={styles.dot} style={{ background: '#58cb42' }} />
          </div>
          <div className={styles.browserWindowAddressBar}>{url}</div>
          <div className={styles.browserWindowMenuIcon}>
            <div>
              <span className={styles.bar} />
              <span className={styles.bar} />
              <span className={styles.bar} />
            </div>
          </div>
        </div>

        <div className={styles.browserWindowBody}>
          {imgSrc ? <img src={imgSrc} /> : children}
        </div>
      </div>
    </div>
  );
}

export default BrowserWindow;
