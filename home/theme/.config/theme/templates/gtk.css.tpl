/* managed by theme */

/* adw-gtk3 and libadwaita before 1.6. */
@define-color window_bg_color {{ background }};
@define-color window_fg_color {{ foreground }};
@define-color view_bg_color {{ dark_background }};
@define-color view_fg_color {{ foreground }};

@define-color headerbar_bg_color {{ lighter_background }};
@define-color headerbar_fg_color {{ foreground }};
@define-color headerbar_border_color {{ foreground }};
@define-color headerbar_backdrop_color mix({{ background }}, {{ lighter_background }}, 0.5);
@define-color headerbar_shade_color {{ darker_background | rgba:0.36 }};
@define-color headerbar_darker_shade_color {{ darker_background | rgba:0.9 }};

@define-color sidebar_bg_color {{ lighter_background }};
@define-color sidebar_fg_color {{ foreground }};
@define-color sidebar_backdrop_color mix({{ background }}, {{ lighter_background }}, 0.5);
@define-color sidebar_shade_color {{ darker_background | rgba:0.25 }};
@define-color sidebar_border_color {{ darker_background | rgba:0.36 }};
@define-color secondary_sidebar_bg_color mix({{ background }}, {{ lighter_background }}, 0.25);
@define-color secondary_sidebar_fg_color {{ foreground }};
@define-color secondary_sidebar_backdrop_color {{ background }};
@define-color secondary_sidebar_shade_color {{ darker_background | rgba:0.25 }};
@define-color secondary_sidebar_border_color {{ darker_background | rgba:0.36 }};

@define-color card_bg_color mix({{ background }}, {{ lighter_background }}, 0.55);
@define-color card_fg_color {{ foreground }};
@define-color card_shade_color {{ darker_background | rgba:0.36 }};
@define-color dialog_bg_color {{ lighter_background }};
@define-color dialog_fg_color {{ foreground }};
@define-color popover_bg_color {{ lighter_background }};
@define-color popover_fg_color {{ foreground }};
@define-color popover_shade_color {{ darker_background | rgba:0.25 }};
@define-color thumbnail_bg_color {{ lighter_background }};
@define-color thumbnail_fg_color {{ foreground }};

@define-color accent_color {{ accent }};
@define-color accent_bg_color {{ accent }};
@define-color accent_fg_color {{ on_accent }};
@define-color destructive_color {{ red }};
@define-color destructive_bg_color {{ red }};
@define-color destructive_fg_color {{ on_accent }};
@define-color success_color {{ green }};
@define-color success_bg_color {{ green }};
@define-color success_fg_color {{ on_accent }};
@define-color warning_color {{ yellow }};
@define-color warning_bg_color {{ yellow }};
@define-color warning_fg_color {{ on_accent }};
@define-color error_color {{ red }};
@define-color error_bg_color {{ red }};
@define-color error_fg_color {{ on_accent }};

@define-color shade_color {{ darker_background | rgba:0.25 }};
@define-color scrollbar_outline_color {{ darker_background | rgba:0.95 }};
@define-color overview_bg_color {{ darker_background }};
@define-color overview_fg_color {{ foreground }};
@define-color panel_bg_color {{ dark_background }};
@define-color panel_fg_color {{ foreground }};

/* GTK3 compatibility names used by older applications and window decorations. */
@define-color theme_fg_color @window_fg_color;
@define-color theme_text_color @view_fg_color;
@define-color theme_bg_color @window_bg_color;
@define-color theme_base_color @view_bg_color;
@define-color theme_selected_bg_color @accent_bg_color;
@define-color theme_selected_fg_color @accent_fg_color;
@define-color insensitive_bg_color mix(@window_bg_color, @view_bg_color, 0.4);
@define-color insensitive_fg_color {{ text_muted }};
@define-color insensitive_base_color @view_bg_color;
@define-color theme_unfocused_fg_color {{ text_muted }};
@define-color theme_unfocused_text_color {{ text_muted }};
@define-color theme_unfocused_bg_color @window_bg_color;
@define-color theme_unfocused_base_color @view_bg_color;
@define-color theme_unfocused_selected_bg_color @accent_bg_color;
@define-color theme_unfocused_selected_fg_color @accent_fg_color;
@define-color unfocused_insensitive_color {{ text_faint }};
@define-color borders {{ foreground | rgba:0.15 }};
@define-color unfocused_borders {{ foreground | rgba:0.1 }};
@define-color wm_title {{ foreground }};
@define-color wm_unfocused_title {{ text_muted }};
@define-color wm_highlight {{ darker_background }};
@define-color wm_borders_edge {{ foreground | rgba:0.07 }};
@define-color wm_bg_a @headerbar_bg_color;
@define-color wm_bg_b @window_bg_color;
@define-color wm_shadow {{ darker_background | rgba:0.35 }};
@define-color wm_border {{ darker_background | rgba:0.18 }};
@define-color wm_button_hover_color_a @headerbar_bg_color;
@define-color wm_button_hover_color_b @window_bg_color;
@define-color wm_button_active_color_a @view_bg_color;
@define-color wm_button_active_color_b @view_bg_color;
@define-color wm_button_active_color_c @view_bg_color;
@define-color content_view_bg @view_bg_color;
@define-color text_view_bg @view_bg_color;

/* libadwaita 1.6+ uses CSS variables instead of the named colours above.
 * GTK3 skips :root with a parsing warning; the named colours remain loaded.
 */
:root {
  --window-bg-color: {{ background }};
  --window-fg-color: {{ foreground }};
  --view-bg-color: {{ dark_background }};
  --view-fg-color: {{ foreground }};

  --headerbar-bg-color: {{ lighter_background }};
  --headerbar-fg-color: {{ foreground }};
  --headerbar-border-color: {{ foreground }};
  --headerbar-backdrop-color: mix({{ background }}, {{ lighter_background }}, 0.5);
  --headerbar-shade-color: {{ darker_background | rgba:0.36 }};
  --headerbar-darker-shade-color: {{ darker_background | rgba:0.9 }};

  --sidebar-bg-color: {{ lighter_background }};
  --sidebar-fg-color: {{ foreground }};
  --sidebar-backdrop-color: mix({{ background }}, {{ lighter_background }}, 0.5);
  --sidebar-shade-color: {{ darker_background | rgba:0.25 }};
  --sidebar-border-color: {{ darker_background | rgba:0.36 }};
  --secondary-sidebar-bg-color: mix({{ background }}, {{ lighter_background }}, 0.25);
  --secondary-sidebar-fg-color: {{ foreground }};
  --secondary-sidebar-backdrop-color: {{ background }};
  --secondary-sidebar-shade-color: {{ darker_background | rgba:0.25 }};
  --secondary-sidebar-border-color: {{ darker_background | rgba:0.36 }};

  --card-bg-color: mix({{ background }}, {{ lighter_background }}, 0.55);
  --card-fg-color: {{ foreground }};
  --card-shade-color: {{ darker_background | rgba:0.36 }};
  --dialog-bg-color: {{ lighter_background }};
  --dialog-fg-color: {{ foreground }};
  --popover-bg-color: {{ lighter_background }};
  --popover-fg-color: {{ foreground }};
  --popover-shade-color: {{ darker_background | rgba:0.25 }};
  --thumbnail-bg-color: {{ lighter_background }};
  --thumbnail-fg-color: {{ foreground }};

  --accent-color: {{ accent }};
  --accent-bg-color: {{ accent }};
  --accent-fg-color: {{ on_accent }};
  --destructive-color: {{ red }};
  --destructive-bg-color: {{ red }};
  --destructive-fg-color: {{ on_accent }};
  --success-color: {{ green }};
  --success-bg-color: {{ green }};
  --success-fg-color: {{ on_accent }};
  --warning-color: {{ yellow }};
  --warning-bg-color: {{ yellow }};
  --warning-fg-color: {{ on_accent }};
  --error-color: {{ red }};
  --error-bg-color: {{ red }};
  --error-fg-color: {{ on_accent }};

  --shade-color: {{ darker_background | rgba:0.25 }};
  --scrollbar-outline-color: {{ darker_background | rgba:0.95 }};
  --overview-bg-color: {{ darker_background }};
  --overview-fg-color: {{ foreground }};
}
