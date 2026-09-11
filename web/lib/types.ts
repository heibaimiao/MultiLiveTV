export interface Source {
  id: number;
  name: string;
  url: string;
  flag: number;
  jx_url?: string;
  json_parse?: string;
  danmaku_api_url?: string;
  vip_only?: boolean;
}

export interface VodType {
  type_id: number;
  type_name: string;
}

export interface VodItem {
  vod_id: string;
  vod_name: string;
  vod_pic: string;
  vod_remarks?: string;
  vod_year?: string;
  vod_area?: string;
  vod_class?: string;
  vod_blurb?: string;
  vod_content?: string;
  vod_play_from?: string;
  vod_play_url?: string;
  /** MacCMS update time (unix seconds or datetime string) */
  vod_time?: string | number;
  /** MacCMS created/add time fallback */
  vod_time_add?: string | number;
  type_id?: number;
  type_name?: string;
}

export interface Episode {
  name: string;
  url: string;
}

export interface PlaySource {
  name: string;
  key: string;
  episodes: Episode[];
  sourceId?: number;
  weight?: number;
  mode?: "direct" | "ticket";
  playFrom?: string;
  providerId?: string;
  ticket?: string;
  requiresAuth?: boolean;
}

export interface PlayResolveRequest {
  mode: "direct" | "ticket";
  sourceId?: number;
  url?: string;
  jx?: boolean;
  ticket?: string;
  providerId?: string;
  playFrom?: string;
}

export interface VodVariant {
  sourceId: number;
  sourceName: string;
  vodId: string;
}

export interface MergedVodItem extends VodItem {
  variants: VodVariant[];
  primarySourceId: number;
}

export interface MacCmsListResponse {
  code: number;
  msg: string;
  page: number;
  pagecount: number;
  limit: string;
  total: number;
  list: VodItem[];
  class?: VodType[];
}

export interface MacCmsDetailResponse {
  code: number;
  msg: string;
  list: VodItem[];
}

export interface SearchResultItem extends VodItem {
  sourceId: number;
  sourceName: string;
}

export type MergeableVodItem = VodItem & {
  sourceId?: number;
  sourceName?: string;
};

export interface ParseResult {
  url: string;
  parsed: boolean;
  mode?: string;
  expiresAt?: number | null;
}
