-- Admin-controlled global website palette. Safe additive migration; preserves existing data.
alter table public.site_customization
  add column if not exists theme_colors jsonb not null default
  '{}'::jsonb;

create or replace function public.admin_save_theme_colors(_colors jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  k text;
  v text;
  allowed text[] := array['bg','panel','card','text','muted','border','primary','accent','success','danger'];
begin
  if not public.is_active_admin('appearance') then
    raise exception 'Not authorized';
  end if;
  if jsonb_typeof(_colors) <> 'object' then
    raise exception 'Invalid color settings';
  end if;
  foreach k in array allowed loop
    v := _colors ->> k;
    if v is null or v !~ '^#[0-9A-Fa-f]{6}$' then
      raise exception 'Invalid color value for %', k;
    end if;
  end loop;
  update public.site_customization
  set theme_colors = jsonb_build_object(
    'bg',_colors->>'bg','panel',_colors->>'panel','card',_colors->>'card',
    'text',_colors->>'text','muted',_colors->>'muted','border',_colors->>'border',
    'primary',_colors->>'primary','accent',_colors->>'accent',
    'success',_colors->>'success','danger',_colors->>'danger'
  ),
  primary_color = _colors->>'primary',
  accent_color = _colors->>'accent',
  updated_at = now()
  where id = 1;
end;
$$;

revoke all on function public.admin_save_theme_colors(jsonb) from public, anon;
grant execute on function public.admin_save_theme_colors(jsonb) to authenticated;
