# AHSAN SPORT Admin — Supabase-connected starter

This package includes the Sorani Kurdish RTL dashboard preview and a browser-side Supabase client setup using the project URL and publishable key supplied by the owner.

## Important status
- Supabase client configuration is included.
- The existing dashboard sections are still a UI prototype; their tables/forms are not yet wired to database CRUD operations.
- Do not treat demo counts or placeholder rows as live business data.
- The app does not contain a service-role/secret key.

## Run locally
Because this uses JavaScript ES modules, serve this folder from a local web server (not by opening `index.html` as a `file://` URL). For example, with Node installed:

```bash
npx serve .
```

Then open the local URL shown by the server.

## Supabase setup
The client reads `supabase-config.js` and uses `@supabase/supabase-js` from the official CDN. The browser key is the publishable key and relies on the project's RLS policies for access control. Never add a secret/service_role key to browser files.

## Next implementation step
Wire authentication and each module to the existing schema (`profiles`, `products`, `inventory_variants`, `orders`, `expenses`, `product_submissions`) after confirming each table's columns and RLS permissions. Do not enable write actions until their policies are confirmed.
