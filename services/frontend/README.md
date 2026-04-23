# ShopCloud frontend

Tiny vanilla-JS storefront that talks to the backend microservices through the public ALB. Designed to be dead-simple to re-skin.

## To change the style

Open `styles/theme.css`. **Everything else reads from there.** Change the CSS variables (colors, fonts, radius, spacing) and the whole UI updates:

```css
:root {
  --color-bg:      #0b1020;   /* page background */
  --color-surface: #141a2e;   /* cards, nav bar */
  --color-accent:  #6ee7b7;   /* CTA + prices */
  --color-accent-2:#60a5fa;   /* links */
  /* ... */
}
```

Add `class="light"` to the root element (or rely on `prefers-color-scheme: light`) to flip to the built-in light theme.

## Local dev

```bash
cd services/frontend
docker build -t shopcloud-frontend .
docker run --rm -p 8080:8080 shopcloud-frontend
open http://localhost:8080
```

The `/api/*` calls will fail locally (no backend) — point the browser console at a live cluster or stub the `fetch` calls in `app.js` for dev.

## Deploy

CI/CD matrix-builds this image alongside the backend services and pushes to ECR (`shopcloud/frontend`). The `k8s/base/frontend/frontend.yaml` manifest deploys it; the public Ingress routes `/` (anything not `/api/*`) to it.
