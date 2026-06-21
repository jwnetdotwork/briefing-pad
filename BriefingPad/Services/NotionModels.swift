import Foundation

struct NotionBlockList: Decodable {
    let results: [NotionBlock]
    let has_more: Bool
    let next_cursor: String?
}

struct NotionBlock: Decodable {
    let id: String
    let type: String
    let has_children: Bool
    let last_edited_time: String?
    let parent: NotionBlockParent?
    let heading_2: NotionHeading?
    let heading_3: NotionHeading?
    let heading_4: NotionHeading?
    let paragraph: NotionTextContent?
    let bulleted_list_item: NotionTextContent?
    let image: NotionImage?

    enum CodingKeys: String, CodingKey {
        case id, type, has_children, last_edited_time, parent, heading_2, heading_3, heading_4, paragraph, bulleted_list_item, image
    }
}

struct NotionBlockParent: Decodable {
    let type: String
    let page_id: String?
    let block_id: String?
}

struct NotionPage: Decodable {
    let id: String
    let properties: [String: NotionProperty]

    struct NotionProperty: Decodable {
        let type: String
        let title: [NotionRichText]?
    }

    var title: String {
        properties.values.first(where: { $0.type == "title" })?.title?.map { $0.plain_text }.joined() ?? "無題のセッション"
    }
}

struct NotionUser: Decodable {
    let id: String
}

struct NotionHeading: Decodable {
    let rich_text: [NotionRichText]
}

struct NotionTextContent: Decodable {
    let rich_text: [NotionRichText]
}

struct NotionRichText: Decodable {
    let plain_text: String
}

struct NotionImage: Decodable {
    let caption: [NotionRichText]
    let type: String
    let external: NotionExternal?
    let file: NotionFile?
}

struct NotionExternal: Decodable {
    let url: String
}

struct NotionFile: Decodable {
    let url: String
}
