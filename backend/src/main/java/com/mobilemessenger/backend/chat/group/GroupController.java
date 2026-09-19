package com.mobilemessenger.backend.chat.group;

import com.mobilemessenger.backend.chat.group.dto.CreateGroupRequest;
import com.mobilemessenger.backend.chat.group.dto.GroupDetailsResponse;
import com.mobilemessenger.backend.chat.group.dto.InviteToGroupRequest;
import com.mobilemessenger.backend.chat.group.dto.PendingGroupInvitationResponse;
import jakarta.validation.Valid;
import java.util.List;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/groups")
public class GroupController {

    private final GroupService groupService;

    public GroupController(GroupService groupService) {
        this.groupService = groupService;
    }

    @PostMapping
    public ResponseEntity<GroupDetailsResponse> create(
            Authentication authentication, @Valid @RequestBody CreateGroupRequest request) {
        GroupDetailsResponse group =
                groupService.createGroup(currentUserId(authentication), request.name(), request.memberIds());
        return ResponseEntity.status(HttpStatus.CREATED).body(group);
    }

    @GetMapping("/{groupId}")
    public GroupDetailsResponse get(Authentication authentication, @PathVariable UUID groupId) {
        return groupService.getGroup(groupId, currentUserId(authentication));
    }

    @PostMapping("/{groupId}/invitations")
    public GroupDetailsResponse invite(
            Authentication authentication,
            @PathVariable UUID groupId,
            @Valid @RequestBody InviteToGroupRequest request) {
        return groupService.invite(groupId, currentUserId(authentication), request.userIds());
    }

    @GetMapping("/invitations/pending")
    public List<PendingGroupInvitationResponse> pending(Authentication authentication) {
        return groupService.listPendingInvitations(currentUserId(authentication));
    }

    @PostMapping("/invitations/{invitationId}/accept")
    public GroupDetailsResponse accept(Authentication authentication, @PathVariable UUID invitationId) {
        return groupService.acceptInvitation(invitationId, currentUserId(authentication));
    }

    @PostMapping("/invitations/{invitationId}/decline")
    public ResponseEntity<Void> decline(Authentication authentication, @PathVariable UUID invitationId) {
        groupService.declineInvitation(invitationId, currentUserId(authentication));
        return ResponseEntity.noContent().build();
    }

    private UUID currentUserId(Authentication authentication) {
        return (UUID) authentication.getPrincipal();
    }
}
